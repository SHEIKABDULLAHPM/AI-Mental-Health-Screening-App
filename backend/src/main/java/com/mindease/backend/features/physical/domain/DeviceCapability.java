package com.mindease.backend.features.physical.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Verified (or explicitly unverified) capability of one device for one metric.
 *
 * <p>This is the single source of truth the dashboard and the insight engine
 * use to decide whether a metric may be shown as measured, shown as "device
 * does not support this", or omitted entirely.</p>
 */
@Document(collection = "device_capabilities")
@CompoundIndex(name = "uq_device_metric",
        def = "{'userId': 1, 'deviceId': 1, 'metric': 1}", unique = true)
@CompoundIndex(name = "user_device", def = "{'userId': 1, 'deviceId': 1}")
public class DeviceCapability {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String deviceId;

    private String deviceModel;

    private String firmwareVersion;

    private String metric;

    private CapabilitySupportStatus supportStatus = CapabilitySupportStatus.UNKNOWN;

    private CapabilityRetrievalMethod retrievalMethod = CapabilityRetrievalMethod.NONE;

    /** Free-form, user-safe note about what is known to be limited. */
    private String limitations;

    /** When the capability was last checked on real hardware, if ever. */
    private Instant lastVerifiedAt;

    private Instant updatedAt;

    public DeviceCapability() {
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

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
    }

    public String getDeviceModel() {
        return deviceModel;
    }

    public void setDeviceModel(String deviceModel) {
        this.deviceModel = deviceModel;
    }

    public String getFirmwareVersion() {
        return firmwareVersion;
    }

    public void setFirmwareVersion(String firmwareVersion) {
        this.firmwareVersion = firmwareVersion;
    }

    public String getMetric() {
        return metric;
    }

    public void setMetric(String metric) {
        this.metric = metric;
    }

    public CapabilitySupportStatus getSupportStatus() {
        return supportStatus;
    }

    public void setSupportStatus(CapabilitySupportStatus supportStatus) {
        this.supportStatus = supportStatus;
    }

    public CapabilityRetrievalMethod getRetrievalMethod() {
        return retrievalMethod;
    }

    public void setRetrievalMethod(CapabilityRetrievalMethod retrievalMethod) {
        this.retrievalMethod = retrievalMethod;
    }

    public String getLimitations() {
        return limitations;
    }

    public void setLimitations(String limitations) {
        this.limitations = limitations;
    }

    public Instant getLastVerifiedAt() {
        return lastVerifiedAt;
    }

    public void setLastVerifiedAt(Instant lastVerifiedAt) {
        this.lastVerifiedAt = lastVerifiedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }
}
