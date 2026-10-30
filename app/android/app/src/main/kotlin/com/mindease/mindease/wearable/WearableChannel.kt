/*
 * MethodChannel `mindease/wearable`: bridges the Flutter `WearableGateway`
 * abstraction to the FitPro BLE client.
 *
 * The Dart side degrades gracefully (MissingPluginException / PlatformException
 * -> safe defaults), so this channel is only ever exercised on Android where
 * a real FitPro band exists. Operations are single-flight; concurrent calls
 * reply with a BUSY error instead of corrupting the GATT session.
 *
 * Focused scope for Phase 1:
 *   - scan for nearby FitPro bands
 *   - connect, discover the UART bridge, enable notifications
 *   - readSnapshot(): standard battery/device-info reads + a bounded
 *     history-fetch window that decodes step/sleep/heart-rate/day-totals
 *     frames and ACKs the band's gate frames so it streams the rest.
 *   - start/stopHeartRateMonitor(): live heart-rate measurement streamed as
 *     events on `mindease/wearable/events` (no synthetic samples: a silent
 *     band yields zero events, never a placeholder reading).
 *
 * All GATT callbacks land on the main looper: BLE callbacks arrive on binder
 * threads but MethodChannel results must be published on the main thread and
 * the GATT session state must not be mutated from two threads.
 */
package com.mindease.mindease.wearable

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.util.Log
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.ArrayDeque

/**
 * MethodChannel handler for the wearable bridge.
 *
 * Instantiated by [com.mindease.mindease.MainActivity] via [attach], which also
 * forwards the activity's `onRequestPermissionsResult`. The standard
 * FlutterPlugin/ActivityAware entry points are kept for potential future use
 * but are not exercised by the current wiring.
 */
class WearableChannel : MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    private val TAG: String = "WearableChannel"

    /** How long a standard GATT read may stay unanswered before it is skipped. */
    private val READ_TIMEOUT_MILLIS = 2_500L

    constructor()

    constructor(activity: Activity, messenger: BinaryMessenger) : this() {
        attach(activity, messenger)
    }

    private var activity: Activity? = null
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val zone: ZoneId = ZoneId.systemDefault()

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var gatt: BluetoothGatt? = null
    private var deviceAddress: String? = null
    private var notificationsOn = false
    private var uartVariant: FitProProtocol.UartVariant? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null

    private var scanning = false
    private var scanPending: MethodChannel.Result? = null
    private val scanResults = LinkedHashMap<String, Map<String, Any?>>()
    private var scanCallback: ScanCallback? = null
    private var scanTimeout: Runnable? = null

    private var connecting = false
    private var connectPending: MethodChannel.Result? = null
    private var connectTimeout: Runnable? = null

    /** True only after the platform reports STATE_CONNECTED. */
    private var gattConnected = false
    private var snapshotActive = false
    private var snapshotResult: MethodChannel.Result? = null
    private var snapshotTimeout: Runnable? = null
    /** Guards the standard GATT reads: a band that stops answering must not
     *  hold the snapshot call open until the watchdog. */
    private var readTimeout: Runnable? = null
    private var activeRead: BluetoothGattCharacteristic? = null
    /** Reassembles frames split across BLE notifications (see [FitProProtocol.FrameAssembler]). */
    private val frameAssembler = FitProProtocol.FrameAssembler()
    private val pendingReads = ArrayDeque<BluetoothGattCharacteristic>()
    private val pendingAcks = ArrayDeque<ByteArray>()
    private var fetchFinishPending = false
    /**
     * Elapsed-realtime of the last parsed band frame, and how many times the
     * collection window was extended. A band with a deep history (or a slow
     * link) may still be streaming when the base window ends; the window
     * then grows in bounded 4 s steps instead of truncating the stream —
     * while a silent band still finishes on time.
     */
    private var lastChunkAt = 0L
    private var finishExtensions = 0
    /**
     * True while the paced init preamble is still being written. ACKs queued
     * from early band notifications must wait: [onCharacteristicWrite] fires
     * for preamble writes too, and draining ACKs mid-preamble interleaves
     * them with init commands the band must process in order.
     */
    private var preambleActive = false

    private val stepChunks = ArrayList<FitProProtocol.StepChunk>()
    private val sleepChunks = ArrayList<FitProProtocol.SleepChunk>()
    private val hrSamples = ArrayList<Pair<LocalDate, FitProProtocol.HeartRateSample>>()
    private var firmware: String? = null
    private var batteryLevel: Int? = null
    private var modelName: String? = null
    /**
     * Protocol frames received during the current snapshot. Zero means the
     * band acknowledged the connection but never streamed history — reported
     * to Dart as `dataComplete: false` so an empty read is never enqueued as
     * a successful sync (a fixed delay alone is not proof of completion).
     */
    private var framesReceived = 0

    private val isoInstant = DateTimeFormatter.ISO_INSTANT
    private val isoDate = DateTimeFormatter.ISO_LOCAL_DATE

    private var permissionRequestCode = 0
    private val pendingPermissions = ArrayDeque<MethodChannel.Result>()

    // ── Live heart-rate monitoring ───────────────────────────────────────
    /**
     * EventChannel `mindease/wearable/events` streams decoded live samples
     * while a monitor session is running. Events carry only what the band
     * actually reported (bpm + timestamps + provenance) — never a synthetic
     * waveform or an interpolated value.
     */
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var monitorActive = false
    private var monitorPending: MethodChannel.Result? = null
    private var monitorPreamble: Runnable? = null

    // ── Lifefefycle ─────────────────────────────────────────────────────────

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        this.activity = activity
        this.context = activity.applicationContext
        this.bluetoothAdapter =
            (context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        channel = MethodChannel(messenger, "mindease/wearable").also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, "mindease/wearable/events").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    fun detach() {
        stopScan()
        cancelConnect()
        cancelSnapshot()
        cancelMonitor("detached")
        preambleActive = false
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (_: Exception) {
        }
        gatt = null
        deviceAddress = null
        notificationsOn = false
        uartVariant = null
        writeCharacteristic = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        activity = null
    }

    // ── MethodChannel ──────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isAvailable())
            "bluetoothState" -> result.success(bluetoothState())
            "hasPermissions" -> result.success(hasRequiredPermissions())
            "requestPermissions" -> requestPermissions(result)
            "scan" -> scan(call, result)
            "connect" -> connect(call, result)
            "disconnect" -> {
                disconnectDevice()
                result.success(null)
            }
            "readSnapshot" -> readSnapshot(result)
            "startHeartRateMonitor" -> startHeartRateMonitor(result)
            "stopHeartRateMonitor" -> stopHeartRateMonitor(result)
            else -> result.notImplemented()
        }
    }

    // ── Availability / permissions ─────────────────────────────────────────

    private fun isAvailable(): Boolean {
        val ctx = context ?: return false
        val hasFeature = ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        val hasAdapter = bluetoothAdapter?.isEnabled == true
        return hasFeature && hasAdapter
    }

    /**
     * Distinguishes the three adapter states the Dart layer reports
     * separately: "unsupported" (no BLE hardware), "off" (adapter present but
     * disabled), "on". [isAvailable] stays as the legacy combined check.
     */
    private fun bluetoothState(): String {
        val ctx = context ?: return "unsupported"
        if (!ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            return "unsupported"
        }
        val adapter = bluetoothAdapter ?: return "off"
        return if (adapter.isEnabled) "on" else "off"
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasRequiredPermissions(): Boolean {
        val act = activity ?: return false
        return requiredPermissions().all {
            ActivityCompat.checkSelfPermission(act, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.success(false)
            return
        }
        if (hasRequiredPermissions()) {
            result.success(true)
            return
        }
        permissionRequestCode++
        pendingPermissions.addLast(result)
        ActivityCompat.requestPermissions(act, requiredPermissions(), permissionRequestCode)
    }

    /** Forwarded from `MainActivity.onRequestPermissionsResult`. */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != permissionRequestCode || pendingPermissions.isEmpty()) return false
        val ok = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val p = pendingPermissions.removeFirst()
        main.post { p.success(ok) }
        return true
    }

    // ── Scan ───────────────────────────────────────────────────────────────

    private fun scan(call: MethodCall, result: MethodChannel.Result) {
        if (scanning) {
            result.error("BUSY", "scan already running", null)
            return
        }
        if (!hasRequiredPermissions()) {
            result.error("PERMISSION_REQUIRED", "bluetooth permission missing", null)
            return
        }
        val scanner = bluetoothAdapter?.bluetoothLeScanner
        if (scanner == null || bluetoothAdapter?.isEnabled != true) {
            result.error("BLUETOOTH_OFF", "bluetooth adapter unavailable", null)
            return
        }
        val timeoutMillis = (call.argument<Number>("timeoutMillis")?.toLong() ?: 6_000L)
            .coerceIn(1_000L, 30_000L)

        scanning = true
        scanPending = result
        scanResults.clear()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, res: ScanResult) {
                val device = res.device ?: return
                val address = device.address ?: return
                if (!scanResults.containsKey(address)) {
                    scanResults[address] = mapOf(
                        "deviceIdentifier" to address,
                        "name" to (device.name ?: ""),
                        "rssi" to res.rssi,
                    )
                }
            }

            override fun onScanFailed(errorCode: Int) {
                finishScan("SCAN_FAILED", errorCode)
            }
        }
        scanCallback = callback
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(null, settings, callback)
        } catch (e: SecurityException) {
            scanning = false
            scanPending = null
            result.error("PERMISSION_REQUIRED", e.message, null)
            return
        } catch (e: Exception) {
            scanning = false
            scanPending = null
            result.error("SCAN_FAILED", e.message, null)
            return
        }
        val timeout = Runnable { finishScan(null, 0) }
        scanTimeout = timeout
        main.postDelayed(timeout, timeoutMillis)
    }

    private fun finishScan(error: String?, errorCode: Int) {
        scanTimeout?.let { main.removeCallbacks(it) }
        scanTimeout = null
        val pending = scanPending ?: return
        scanPending = null
        scanning = false
        scanCallback?.let { cb ->
            try {
                bluetoothAdapter?.bluetoothLeScanner?.stopScan(cb)
            } catch (_: Exception) {
            }
        }
        scanCallback = null
        if (error != null) {
            pending.error(error, "scan failed ($errorCode)", null)
        } else {
            val nearestFirst = scanResults.values.sortedByDescending {
                (it["rssi"] as? Int) ?: Int.MIN_VALUE
            }
            pending.success(nearestFirst.toList())
        }
    }

    private fun stopScan() {
        if (scanning) finishScan(null, 0)
    }

    // ── Connect ────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (connecting) {
            result.error("BUSY", "connect already running", null)
            return
        }
        if (snapshotActive) {
            result.error("BUSY", "snapshot in progress", null)
            return
        }
        if (!hasRequiredPermissions()) {
            result.error("PERMISSION_REQUIRED", "bluetooth permission missing", null)
            return
        }
        val address = call.argument<String>("deviceIdentifier")
            ?: run {
                result.error("BAD_ARGUMENT", "deviceIdentifier required", null)
                return
            }
        // Idempotent reconnect: when an established session exists for the
        // same device (the automatic sync after pairing, the session's
        // auto-sync on dashboard open), replying success is cheaper and safer
        // than opening a second GATT object over the live one, which would
        // orphan the previous connection until disconnect.
        if (gatt != null && deviceAddress == address && notificationsOn && gattConnected) {
            Log.d(TAG, "connect: already connected to $address, short-circuiting")
            result.success(true)
            return
        }
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "bluetooth adapter unavailable", null)
            return
        }
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            result.error("BAD_ARGUMENT", "invalid device address", null)
            return
        }
        connecting = true
        connectPending = result
        val timeout = Runnable {
            connecting = false
            gattConnected = false
            val r = connectPending
            connectPending = null
            r?.success(false)
            // Service discovery on this band can take 8-12 s; a timeout must
            // fully close the half-open GATT or the next connect reuses a
            // zombie handle and short-circuits without TX.
            try {
                gatt?.disconnect()
                gatt?.close()
            } catch (_: Exception) {
            }
            gatt = null
            deviceAddress = null
        }
        connectTimeout = timeout
        main.postDelayed(timeout, 25_000L)
        try {
            gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: Exception) {
            connecting = false
            connectTimeout?.let { main.removeCallbacks(it) }
            result.error("CONNECT_FAILED", e.message, null)
        }
    }

    private fun cancelConnect() {
        connectTimeout?.let { main.removeCallbacks(it) }
        connectTimeout = null
        val r = connectPending
        if (r != null) {
            connectPending = null
            connecting = false
            r.success(false)
        }
    }

    private fun disconnectDevice() {
        cancelConnect()
        cancelSnapshot()
        clearReadTimeout()
        preambleActive = false
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (_: Exception) {
        }
        gatt = null
        deviceAddress = null
        gattConnected = false
        notificationsOn = false
        uartVariant = null
        writeCharacteristic = null
    }

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(gattParam: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                when {
                    newState == BluetoothProfile.STATE_CONNECTED -> {
                        Log.d(TAG, "onConnectionStateChange CONNECTED status=$status device=${gattParam.device?.address}")
                        gattConnected = true
                        // Do NOT call requestMtu here: Android runs one GATT
                        // operation at a time, and an MTU exchange still in
                        // flight makes this discoverServices() return false
                        // silently. The service discovery then never completes
                        // and the connect timeout tears the link down. This
                        // band keeps MTU 23 anyway; FrameAssembler reassembles
                        // the resulting 20-byte fragments.
                        try {
                            gattParam.discoverServices()
                        } catch (_: Exception) {
                        }
                    }
                    newState == BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.d(TAG, "onConnectionStateChange DISCONNECTED status=$status device=${gattParam.device?.address}")
                        connecting = false
                        gattConnected = false
                        notificationsOn = false
                        clearReadTimeout()
                        frameAssembler.reset()
                        cancelMonitor("disconnected")
                        uartVariant = null
                        writeCharacteristic = null
                        connectPending?.let { r ->
                            connectPending = null
                            connectTimeout?.let { main.removeCallbacks(it) }
                            r.success(false)
                        }
                        try {
                            gattParam.close()
                        } catch (_: Exception) {
                        }
                        if (gatt === gattParam) {
                            gatt = null
                            deviceAddress = null
                        }
                    }
                }
            }
        }

        override fun onMtuChanged(gattParam: BluetoothGatt, mtu: Int, status: Int) {
            Log.d(TAG, "onMtuChanged mtu=$mtu status=$status device=${gattParam.device?.address}")
        }

        override fun onServicesDiscovered(gattParam: BluetoothGatt, status: Int) {            main.post {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    Log.d(TAG, "onServicesDiscovered FAILED status=$status device=${gattParam.device?.address}")
                    failConnect(gattParam)
                    return@post
                }
                deviceAddress = gattParam.device?.address
                Log.d(TAG, "onServicesDiscovered OK device=${gattParam.device?.address} services=${gattParam.services?.map { it.uuid }}")
                val variant = FitProProtocol.UART_VARIANTS.firstOrNull {
                    gattParam.getService(it.service) != null
                }
                if (variant == null) {
                    Log.d(TAG, "UART service not found; tried ${FitProProtocol.UART_VARIANTS.map { it.service }}")
                    failConnect(gattParam)
                    return@post
                }
                uartVariant = variant
                Log.d(TAG, "UART variant resolved ${variant.service}")
                val rx = gattParam.getService(variant.service)?.getCharacteristic(variant.notify)
                if (rx == null) {
                    Log.d(TAG, "UART notify characteristic ${variant.notify} not found under ${variant.service}")
                    failConnect(gattParam)
                    return@post
                }
                writeCharacteristic = gattParam.getService(variant.service)?.getCharacteristic(variant.write)
                val cccd = rx.getDescriptor(FitProProtocol.CCCD)
                if (cccd != null) {
                    try {
                        // Both steps are required on Android: registering the
                        // local notification callback and writing the CCCD.
                        // Writing the descriptor alone leaves the stack without
                        // an onCharacteristicChanged callback, so the band can
                        // notify into a void (observed as zero RX frames while
                        // host gatttool received ACKs).
                        gattParam.setCharacteristicNotification(rx, true)
                        cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                        gattParam.writeDescriptor(cccd)
                    } catch (_: Exception) {
                        failConnect(gattParam)
                    }
                } else {
                    notifyReady(gattParam)
                }
            }
        }

        private fun failConnect(gattParam: BluetoothGatt) {
            connecting = false
            gattConnected = false
            notificationsOn = false
            clearReadTimeout()
            uartVariant = null
            writeCharacteristic = null
            connectTimeout?.let { main.removeCallbacks(it) }
            connectPending?.let { it.success(false) }
            connectPending = null
            try {
                gattParam.disconnect()
            } catch (_: Exception) {
            }
        }

        private fun notifyReady(gattParam: BluetoothGatt) {
            notificationsOn = true
            connecting = false
            connectTimeout?.let { main.removeCallbacks(it) }
            connectPending?.let { it.success(true) }
            connectPending = null
        }

        override fun onDescriptorWrite(
            gattParam: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            main.post {
                if (descriptor.uuid == FitProProtocol.CCCD && status == BluetoothGatt.GATT_SUCCESS) {
                        Log.d(TAG, "CCCD write OK -> connected (${gattParam.device?.address})")
                        notifyReady(gattParam)
                    } else if (descriptor.uuid == FitProProtocol.CCCD) {
                        Log.d(TAG, "CCCD write FAILED status=$status -> fail (${gattParam.device?.address})")
                        failConnect(gattParam)
                    }
            }
        }

        override fun onCharacteristicChanged(
            gattParam: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            main.post { onNotification(value) }
        }

        /**
         * Pre-API-33 delivery path. The 3-arg overload above is only invoked
         * on API 33+; without this override notifications never reach
         * [onNotification] on older devices.
         */
        @Deprecated("Used on API < 33")
        override fun onCharacteristicChanged(
            gattParam: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: return
            main.post { onNotification(value) }
        }

        override fun onCharacteristicRead(
            gattParam: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            main.post { onReadComplete(characteristic, status) }
        }

        override fun onCharacteristicWrite(
            gattParam: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            // Preamble writes share this callback: only drain queued ACKs
            // once the init sequence has fully gone out.
            main.post { if (!preambleActive) writeNextAck() }
        }
    }

    /**
     * Writes [payload] to the UART TX characteristic on any API level.
     *
     * The 3-arg `writeCharacteristic(gatt, bytes, writeType)` overload only
     * exists on API 33+; on older devices it would throw NoSuchMethodError,
     * so legacy devices go through the deprecated value-field path.
     */
    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    private fun writeTxCompat(payload: ByteArray) {
        val g = gatt ?: return
        val tx = writeCharacteristic ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(tx, payload, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
            } else {
                tx.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                tx.value = payload
                g.writeCharacteristic(tx)
            }
        } catch (_: Exception) {
        }
    }

    // ── Standard reads ─────────────────────────────────────────────────────

    private fun nextRead() {
        val current = gatt ?: return
        clearReadTimeout()
        if (pendingReads.isEmpty()) {
            beginFetch()
            return
        }
        val characteristic = pendingReads.removeFirst()
        activeRead = characteristic
        val started = try {
            current.readCharacteristic(characteristic)
        } catch (_: Exception) {
            false
        }
        if (!started) {
            // The stack refused the read (busy/dead link). Do not wait for a
            // callback that will never arrive.
            activeRead = null
            main.post { nextRead() }
            return
        }
        val timeout = Runnable {
            if (activeRead === characteristic) {
                Log.d(TAG, "read timeout ${characteristic.uuid}")
                activeRead = null
                nextRead()
            }
        }
        readTimeout = timeout
        main.postDelayed(timeout, READ_TIMEOUT_MILLIS)
    }

    private fun clearReadTimeout() {
        readTimeout?.let { main.removeCallbacks(it) }
        readTimeout = null
        activeRead = null
    }

    private fun onReadComplete(characteristic: BluetoothGattCharacteristic, status: Int) {
        // A late callback for an already-timed-out read must not advance the
        // queue a second time.
        if (activeRead !== characteristic) return
        clearReadTimeout()
        if (status == BluetoothGatt.GATT_SUCCESS) {
            val value = characteristic.value
            if (value != null) onRead(characteristic, value)
        }
        nextRead()
    }

    private fun onRead(characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        when (characteristic.uuid) {
            FitProProtocol.CHAR_BATTERY_LEVEL -> batteryLevel = value.firstOrNull()?.toInt()?.and(0xff)
            FitProProtocol.CHAR_FIRMWARE_REVISION -> firmware = value.decodeUtf8Trimmed()
            FitProProtocol.CHAR_MODEL_NUMBER -> modelName = value.decodeUtf8Trimmed()
        }
    }

    private fun ByteArray.decodeUtf8Trimmed(): String =
        String(this, StandardCharsets.UTF_8).trim { it <= ' ' || it == '\u0000' }

    private fun ByteArray.toHex(): String = joinToString(" ") { "%02x".format(it.toInt() and 0xff) }

    // ── Snapshot ───────────────────────────────────────────────────────────

    private fun readSnapshot(result: MethodChannel.Result) {
        val g = gatt ?: run {
            result.error("NOT_CONNECTED", "no connected device", null)
            return
        }
        if (!notificationsOn || !gattConnected) {
            result.error("NOT_CONNECTED", "device not ready", null)
            return
        }
        if (snapshotActive) {
            result.error("BUSY", "snapshot already running", null)
            return
        }
        // A live monitor and a history fetch would interleave two preambles on
        // the same link; the snapshot supersedes it (the reader re-syncs later).
        cancelMonitor("snapshot")
        snapshotActive = true
        snapshotResult = result
        stepChunks.clear()
        sleepChunks.clear()
        hrSamples.clear()
        firmware = null
        batteryLevel = null
        modelName = null
        pendingReads.clear()
        pendingAcks.clear()
        fetchFinishPending = false
        frameAssembler.reset()
        lastChunkAt = 0L
        finishExtensions = 0
        framesReceived = 0

        val batteryService = g.getService(FitProProtocol.SERVICE_BATTERY)
        val deviceInfo = g.getService(FitProProtocol.SERVICE_DEVICE_INFO)
        batteryService?.getCharacteristic(FitProProtocol.CHAR_BATTERY_LEVEL)?.let {
            pendingReads.addLast(it)
        }
        deviceInfo?.getCharacteristic(FitProProtocol.CHAR_FIRMWARE_REVISION)?.let {
            pendingReads.addLast(it)
        }
        deviceInfo?.getCharacteristic(FitProProtocol.CHAR_MODEL_NUMBER)?.let {
            pendingReads.addLast(it)
        }

        val timeout = Runnable { finishSnapshot("timeout") }
        snapshotTimeout = timeout
        main.postDelayed(timeout, 30_000L)
        nextRead()
    }

    private fun cancelSnapshot() {
        snapshotTimeout?.let { main.removeCallbacks(it) }
        snapshotTimeout = null
        clearReadTimeout()
        fetchFinishPending = false
        preambleActive = false
        pendingReads.clear()
        val r = snapshotResult
        snapshotResult = null
        snapshotActive = false
        r?.error("CANCELLED", "snapshot cancelled", null)
    }

    private fun beginFetch() {
        if (gatt == null || writeCharacteristic == null) {
            finishSnapshot("uart unavailable")
            return
        }
        // Preamble paced 200ms apart. The band must process each command
        // before the next; the full sequence (including language, INIT3 ON and
        // band-info) is required before the band starts streaming data — the
        // Gadgetbridge implementation is explicit that without it "fetch steps
        // doesn't work". Frames are protocol-validated constants-driven data,
        // not logic imports.
        val clock = FitProProtocol.encodeClock(zone = zone)
        val writes = listOf(
            FitProProtocol.frame(FitProProtocol.GROUP_GENERAL, FitProProtocol.CMD_INIT1, byteArrayOf(0x02)),
            FitProProtocol.frame(FitProProtocol.GROUP_GENERAL, FitProProtocol.CMD_SET_DATE_TIME, clock),
            FitProProtocol.frame(FitProProtocol.GROUP_REQUEST_DATA, FitProProtocol.CMD_INIT1),
            FitProProtocol.frame(FitProProtocol.GROUP_REQUEST_DATA, FitProProtocol.CMD_INIT2),
            FitProProtocol.frame(
                FitProProtocol.GROUP_GENERAL,
                FitProProtocol.CMD_SET_LANGUAGE,
                byteArrayOf(FitProProtocol.LANG_ENGLISH.toByte()),
            ),
            FitProProtocol.frame(
                FitProProtocol.GROUP_GENERAL,
                FitProProtocol.CMD_INIT3,
                byteArrayOf(FitProProtocol.VALUE_ON.toByte()),
            ),
            FitProProtocol.frame(
                FitProProtocol.GROUP_REQUEST_DATA,
                FitProProtocol.VALUE_ON,
                byteArrayOf(),
            ),
            FitProProtocol.frame(FitProProtocol.GROUP_REQUEST_DATA, 0x0f),
            FitProProtocol.frame(FitProProtocol.GROUP_REQUEST_DATA, FitProProtocol.CMD_GET_HW_INFO),
            FitProProtocol.frame(
                FitProProtocol.GROUP_BAND_INFO,
                FitProProtocol.CMD_RX_BAND_INFO,
                byteArrayOf(),
            ),
            FitProProtocol.frame(
                FitProProtocol.GROUP_RECEIVE_SPORTS_DATA,
                FitProProtocol.CMD_REQUEST_STEPS_DATA,
                byteArrayOf(FitProProtocol.VALUE_ON.toByte()),
            ),
        )
        var delay = 0L
        preambleActive = true
        for (w in writes) {
            val payload = w
            main.postDelayed({
                try {
                    Log.d(TAG, "TX ${payload.toHex()}")
                    writeTxCompat(payload)
                } catch (_: Exception) {
                }
            }, delay)
            delay += 200
        }
        // Stream the data for a bounded window, then assemble the snapshot.
        // The preamble is fully out by `delay`; ACKs queued meanwhile drain
        // from here on via onCharacteristicWrite. The window extends while
        // the band is actively streaming (see maybeFinishSnapshot).
        main.postDelayed({
            preambleActive = false
            writeNextAck()
        }, delay)
        // Sleep history is a separate 0x15/0x0d request (MFitX
        // `requestSleepHistory`); Gadgetbridge only sends 0x06, which is why
        // our earlier captures never saw a sleep frame. MFitX warns the band
        // dislikes this during its 22:00–09:00 monitoring window, so outside
        // 10:00–21:00 we skip it rather than disturb monitoring.
        if (ZonedDateTime.now(zone).hour in 10..21) {
            val sleepRequest = FitProProtocol.frame(
                FitProProtocol.GROUP_RECEIVE_SPORTS_DATA,
                FitProProtocol.CMD_REQUEST_SLEEP_DATA,
                byteArrayOf(FitProProtocol.VALUE_ON.toByte()),
            )
            main.postDelayed({
                try {
                    Log.d(TAG, "TX ${sleepRequest.toHex()}")
                    writeTxCompat(sleepRequest)
                } catch (_: Exception) {
                }
            }, delay + 1_200L)
        }
        main.postDelayed({ maybeFinishSnapshot() }, delay + 8_000L)
        fetchFinishPending = true
    }

    /**
     * Finishes the snapshot unless the band streamed a frame within the last
     * 1.5 s — in which case the window grows by 4 s, at most three times
     * (base 8 s → cap 20 s). Sleep frames arrive only after the step burst on
     * FitPro, so the old 6 s/2-extension window could close before the band
     * finished replaying them. The 30 s snapshot watchdog still bounds the
     * worst case, so a chatty band can delay but never hang the call.
     */
    private fun maybeFinishSnapshot() {
        if (!snapshotActive) return
        val idleFor = SystemClock.elapsedRealtime() - lastChunkAt
        if (lastChunkAt > 0 && idleFor < 1_500 && finishExtensions < 3) {
            finishExtensions++
            Log.d(TAG, "stream still live; extending fetch window ($finishExtensions/3)")
            main.postDelayed({ maybeFinishSnapshot() }, 4_000L)
            return
        }
        finishSnapshot(null)
    }

    private fun writeNextAck() {
        if (preambleActive) return
        val ack = pendingAcks.peekFirst() ?: return
        if (gatt == null || writeCharacteristic == null) return
        pendingAcks.removeFirst()
        try {
            Log.d(TAG, "ACK ${ack.toHex()}")
            writeTxCompat(ack)
        } catch (_: Exception) {
        }
    }

    private fun onNotification(raw: ByteArray) {
        Log.d(TAG, "RX ${raw.toHex()}")
        for (frame in frameAssembler.feed(raw, SystemClock.elapsedRealtime())) {
            handleFrame(frame)
        }
    }

    private fun handleFrame(frame: FitProProtocol.ParsedFrame) {
        if (snapshotActive) {
            lastChunkAt = SystemClock.elapsedRealtime()
            framesReceived++
            when (frame.group) {
                FitProProtocol.GROUP_RECEIVE_SPORTS_DATA -> when (frame.command) {
                    FitProProtocol.CMD_RX_STEP_DATA -> {
                        FitProProtocol.decodeStepDay(frame).let { stepChunks.addAll(it) }
                        queueAck(frame)
                    }
                    FitProProtocol.CMD_RX_SLEEP_DATA -> {
                        FitProProtocol.decodeSleepDay(frame).let { sleepChunks.addAll(it) }
                        queueAck(frame)
                    }
                    FitProProtocol.CMD_RX_HEART_RATE -> {
                        FitProProtocol.decodeHeartRate(frame)?.let { hr ->
                            val date = stepChunks.firstOrNull()?.date ?: LocalDate.now(zone)
                            hrSamples.add(date to hr)
                        }
                        queueAck(frame)
                    }
                    FitProProtocol.CMD_RX_DAY_TOTALS ->
                        // The 0x0c "day summary" layout is not verified on
                        // V15183 and varied between connections (one capture
                        // decoded to 115,996 steps / 81,247 m for an afternoon).
                        // ACK it so the band keeps streaming, but never turn it
                        // into a reading; step chunks are the verified source.
                        queueAck(frame)
                    FitProProtocol.CMD_RX_STEP_BURST_GATE_1,
                    FitProProtocol.CMD_RX_STEP_BURST_GATE_2,
                    FitProProtocol.CMD_RX_STEP_BURST_GATE_3,
                    -> queueAck(frame)
                    // Unknown sports-data commands still get a receipt ACK so the
                    // band never stalls waiting on an unanswered frame.
                    else -> queueAck(frame)
                }
                FitProProtocol.GROUP_BAND_INFO,
                FitProProtocol.GROUP_REQUEST_DATA,
                -> queueAck(frame)
                // Any other group (bind handshake, button events, future
                // commands): ACK the receipt and ignore the payload rather than
                // leaving the band waiting mid-stream.
                else -> queueAck(frame)
            }
            writeNextAck()
            return
        }
        if (!monitorActive) return
        // Monitoring: stream heart-rate samples out as they arrive and ACK
        // receipt of every parseable frame so the band never stalls waiting
        // on an unanswered one (same flow-control contract as a snapshot).
        if (frame.group == FitProProtocol.GROUP_RECEIVE_SPORTS_DATA &&
            frame.command == FitProProtocol.CMD_RX_HEART_RATE
        ) {
            val sample = FitProProtocol.decodeHeartRate(frame)
            // 0 bpm means "sensor not measuring yet" — a placeholder, never a
            // reading, so it is dropped instead of shown as a heart rate.
            if (sample != null && sample.heartRate in 1..300) emitLiveHeartRate(sample)
        }
        queueAck(frame)
        writeNextAck()
    }

    private fun queueAck(frame: FitProProtocol.ParsedFrame) {
        if (pendingAcks.size < 16) pendingAcks.addLast(FitProProtocol.ackFor(frame))
    }

    // ── Live heart-rate monitoring ───────────────────────────────────────

    /**
     * Starts continuous heart-rate measurement and streams decoded samples
     * over EventChannel `mindease/wearable/events`.
     *
     * Sequence: the documented pair handshake (INIT1) + clock sync first —
     * the same ordering the snapshot preamble uses, because the band ignores
     * measurement commands on a fresh, unsynced link — then the general-group
     * `0x18` measurement-on frame (Gadgetbridge `onHeartRateTest()`). The
     * reply arrives only after that sequence has been paced out, so `true`
     * means "the command sequence left the radio", never "a sample is
     * guaranteed": whether the optical sensor produces data is the band's
     * call, and an empty session is reported as zero samples, not as readings.
     */
    private fun startHeartRateMonitor(result: MethodChannel.Result) {
        val g = gatt ?: run {
            result.error("NOT_CONNECTED", "no connected device", null)
            return
        }
        if (!notificationsOn) {
            result.error("NOT_CONNECTED", "device not ready", null)
            return
        }
        if (snapshotActive) {
            result.error("BUSY", "snapshot already running", null)
            return
        }
        if (monitorActive) {
            result.success(true)
            return
        }
        monitorActive = true
        monitorPending = result
        val clock = FitProProtocol.encodeClock(zone = zone)
        val writes = listOf(
            FitProProtocol.frame(FitProProtocol.GROUP_GENERAL, FitProProtocol.CMD_INIT1, byteArrayOf(0x02)),
            FitProProtocol.frame(FitProProtocol.GROUP_GENERAL, FitProProtocol.CMD_SET_DATE_TIME, clock),
            FitProProtocol.heartRateMonitorFrame(true),
        )
        var delay = 0L
        preambleActive = true
        for (payload in writes) {
            main.postDelayed({
                try {
                    Log.d(TAG, "TX ${payload.toHex()}")
                    writeTxCompat(payload)
                } catch (_: Exception) {
                }
            }, delay)
            delay += 200
        }
        val reply = Runnable {
            monitorPreamble = null
            preambleActive = false
            writeNextAck()
            val pending = monitorPending
            monitorPending = null
            pending?.success(monitorActive && gatt === g)
        }
        monitorPreamble = reply
        main.postDelayed(reply, delay)
    }

    /** Sends measurement-off and ends the session. Idempotent. */
    private fun stopHeartRateMonitor(result: MethodChannel.Result) {
        if (!monitorActive) {
            result.success(false)
            return
        }
        cancelMonitor("stopped", writeOff = true)
        result.success(true)
    }

    /**
     * Tears the monitor down without a GATT write (disconnect/detach) or
     * with one ([writeOff] for an explicit stop), replying to a start that
     * is still in flight and notifying listeners that the stream ended.
     */
    private fun cancelMonitor(reason: String, writeOff: Boolean = false) {
        if (!monitorActive && monitorPending == null && monitorPreamble == null) return
        monitorPreamble?.let { main.removeCallbacks(it) }
        monitorPreamble = null
        monitorActive = false
        preambleActive = false
        monitorPending?.let { it.success(false) }
        monitorPending = null
        if (writeOff) {
            try {
                val off = FitProProtocol.heartRateMonitorFrame(false)
                Log.d(TAG, "TX ${off.toHex()}")
                writeTxCompat(off)
            } catch (_: Exception) {
            }
        }
        val sink = eventSink ?: return
        main.post {
            sink.success(
                hashMapOf<String, Any?>(
                    "event" to "monitorStopped",
                    "reason" to reason,
                    "deviceIdentifier" to deviceAddress,
                ),
            )
        }
    }

    /** Streams one decoded band sample; the sink's thread affinity is main. */
    private fun emitLiveHeartRate(sample: FitProProtocol.HeartRateSample) {
        val sink = eventSink ?: return
        val now = Instant.now()
        val payload = hashMapOf<String, Any?>(
            "event" to "heartRate",
            "bpm" to sample.heartRate,
            "timestamp" to isoInstant.format(liveTimestamp(sample.timeOfDaySeconds, now)),
            "recordedAt" to isoInstant.format(now),
            "measurementType" to "DEVICE_MEASURED",
            "source" to "FITPRO",
            "deviceIdentifier" to deviceAddress,
        )
        if (sample.spo2 in 50..100) payload["spo2"] = sample.spo2
        main.post { sink.success(payload) }
    }

    /**
     * Anchors the band's seconds-of-day field to today's local date. An
     * out-of-range field (band clock not yet synced) falls back to the host
     * receipt time instead of inventing a plausible measurement time.
     */
    private fun liveTimestamp(timeOfDaySeconds: Int, fallback: Instant): Instant {
        if (timeOfDaySeconds < 0 || timeOfDaySeconds > 86_399) return fallback
        return LocalDate.now(zone)
            .atStartOfDay(zone)
            .plusSeconds(timeOfDaySeconds.toLong())
            .toInstant()
    }

    private fun finishSnapshot(error: String?) {
        snapshotTimeout?.let { main.removeCallbacks(it) }
        snapshotTimeout = null
        clearReadTimeout()
        fetchFinishPending = false
        preambleActive = false
        val r = snapshotResult ?: return
        snapshotResult = null
        snapshotActive = false
        if (error != null) {
            r.error("SNAPSHOT_FAILED", error, null)
            return
        }
        val data = LinkedHashMap<String, Any?>()
        data["deviceIdentifier"] = deviceAddress
        firmware?.let { data["firmwareVersion"] = it }
        modelName?.let { data["model"] = it }
        batteryLevel?.let { data["batteryLevel"] = it }
        val capabilityReport = SnapshotAssembler.buildCapabilityReport(
            hasBatteryLevel = batteryLevel != null,
            hasFirmwareVersion = firmware != null,
            hasModelName = modelName != null,
            hasStepChunks = stepChunks.isNotEmpty(),
            hasHeartRate = hrSamples.isNotEmpty(),
            hasSleep = sleepChunks.isNotEmpty(),
            hasSpo2 = hrSamples.any { it.second.spo2 in 50..100 },
        )
        data["capabilities"] = capabilityReport.map { it["metric"] as String }
        data["capabilityReport"] = capabilityReport

        data["readings"] = SnapshotAssembler.buildHeartRateReadings(hrSamples, zone, isoInstant)

        val dailyActivities = SnapshotAssembler.buildDailyActivities(
            stepChunks, zone, isoDate,
        )
        if (dailyActivities.isNotEmpty()) {
            data["dailyActivities"] = dailyActivities
            // Legacy single-day field for older Dart layers: the most recent
            // day (list is sorted ascending).
            data["dailyActivity"] = dailyActivities.last()
        }

        data["sleepSessions"] = SnapshotAssembler.buildSleepSessions(sleepChunks, zone, isoInstant)
        // FitPro does not expose structured workout sessions in this protocol
        // slice; keep the list empty rather than fabricate exercise data.
        data["exerciseSessions"] = emptyList<Map<String, Any?>>()
        // Completeness diagnostics: the Dart layer must not treat an
        // acknowledged-but-silent band as a successful data sync.
        data["framesReceived"] = framesReceived
        data["dataComplete"] = framesReceived > 0
        data["recordedAt"] = isoInstant.format(Instant.now())
        r.success(data)
    }
}