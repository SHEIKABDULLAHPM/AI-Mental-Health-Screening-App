package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A wearable device registered to an authenticated user.
 *
 * <p>{@code userId} is always derived from the authenticated context on the
 * server — it is never taken from the client payload.</p>
 */
@Document(collection = "wearable_devices")
@CompoundIndex(name = "uq_user_device", def = "{'userId': 1, 'deviceIdentifier': 1}", unique = true)
@CompoundIndex(name = "user_updated", def = "{'userId': 1, 'updatedAt': -1}")
public class WearableDevice {

    @Id
    private String id;

    @Indexed
    private String userId;

    private WearableProvider provider;

    private String manufacturer;

    private String model;

    private String firmwareVersion;

    /** Stable device identifier (BLE MAC on Android, opaque id elsewhere). */
    private String deviceIdentifier;

    /**
     * Capability identifiers actually exposed by this device/model (e.g.
     * {@code STEPS}, {@code HEART_RATE}). Capabilities the device does not
     * expose are absent — they are never invented.
     */
    private List<String> capabilities = new ArrayList<>();

    private ConnectionStatus connectionStatus = ConnectionStatus.UNKNOWN;

    /** 0–100 when known, {@code null} when the device never reported it. */
    private Integer batteryLevel;

    /** {@code null} when the device never reported charging state. */
    private Boolean charging;

    private Instant lastConnectedAt;

    private Instant lastSeenAt;

    private Instant lastSyncedAt;

    private Instant createdAt;

    private Instant updatedAt;

    @Version
    private Long documentVersion;

    public WearableDevice() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public WearableProvider getProvider() {
        return provider;
    }

    public void setProvider(WearableProvider provider) {
        this.provider = provider;
    }

    public String getManufacturer() {
        return manufacturer;
    }

    public void setManufacturer(String manufacturer) {
        this.manufacturer = manufacturer;
    }

    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public String getFirmwareVersion() {
        return firmwareVersion;
    }

    public void setFirmwareVersion(String firmwareVersion) {
        this.firmwareVersion = firmwareVersion;
    }

    public String getDeviceIdentifier() {
        return deviceIdentifier;
    }

    public void setDeviceIdentifier(String deviceIdentifier) {
        this.deviceIdentifier = deviceIdentifier;
    }

    public List<String> getCapabilities() {
        return capabilities;
    }

    public void setCapabilities(List<String> capabilities) {
        this.capabilities = capabilities == null ? new ArrayList<>() : capabilities;
    }

    public ConnectionStatus getConnectionStatus() {
        return connectionStatus;
    }

    public void setConnectionStatus(ConnectionStatus connectionStatus) {
        this.connectionStatus = connectionStatus;
    }

    public Integer getBatteryLevel() {
        return batteryLevel;
    }

    public void setBatteryLevel(Integer batteryLevel) {
        this.batteryLevel = batteryLevel;
    }

    public Boolean getCharging() {
        return charging;
    }

    public void setCharging(Boolean charging) {
        this.charging = charging;
    }

    public Instant getLastConnectedAt() {
        return lastConnectedAt;
    }

    public void setLastConnectedAt(Instant lastConnectedAt) {
        this.lastConnectedAt = lastConnectedAt;
    }

    public Instant getLastSeenAt() {
        return lastSeenAt;
    }

    public void setLastSeenAt(Instant lastSeenAt) {
        this.lastSeenAt = lastSeenAt;
    }

    public Instant getLastSyncedAt() {
        return lastSyncedAt;
    }

    public void setLastSyncedAt(Instant lastSyncedAt) {
        this.lastSyncedAt = lastSyncedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public Long getDocumentVersion() {
        return documentVersion;
    }

    public void setDocumentVersion(Long documentVersion) {
        this.documentVersion = documentVersion;
    }
}
