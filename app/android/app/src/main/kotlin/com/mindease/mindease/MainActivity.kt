package com.mindease.mindease

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.mindease.mindease.wearable.WearableChannel

class MainActivity : FlutterActivity() {

    private var wearableChannel: WearableChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val wearable = WearableChannel()
        wearable.attach(this, flutterEngine.dartExecutor.binaryMessenger)
        wearableChannel = wearable
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (wearableChannel?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        wearableChannel?.detach()
        wearableChannel = null
        super.onDestroy()
    }
}