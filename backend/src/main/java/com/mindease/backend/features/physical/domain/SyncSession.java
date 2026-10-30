package com.mindease.backend.features.physical.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Audit record for one synchronization attempt between client and backend.
 * Tracks the fields required for reliable recovery: last successful sync,
 * last attempted sync, status, retry count and error.
 */
@Document(collection = "sync_sessions")
@CompoundIndex(name = "user_started_desc", def = "{'userId': 1, 'startedAt': -1}")
@CompoundIndex(name = "user_status", def = "{'userId': 1, 'status': 1}")
public class SyncSession {

    @Id
    private String id;

    @Indexed
    private String userId;

    /**
     * Client-generated batch id, echoed for every ingestion attempt. The
     * unique sparse index turns a replayed (already-processed) batch into a
     * no-op: the client retries after a lost response, and the server must
     * recognise the batch instead of re-stamping the device and growing the
     * audit log. Sparse because historical rows do not carry the field.
     */
    @Indexed(unique = true, sparse = true)
    private String clientSyncId;

    private String deviceId;

    private WearableProvider provider;

    private SyncStatus status;

    private Instant startedAt;

    private Instant completedAt;

    private int recordsReceived;

    private int recordsAccepted;

    private int recordsRejected;

    private int retryCount;

    private String error;

    public SyncSession() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getClientSyncId() {
        return clientSyncId;
    }

    public void setClientSyncId(String clientSyncId) {
        this.clientSyncId = clientSyncId;
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

    public WearableProvider getProvider() {
        return provider;
    }

    public void setProvider(WearableProvider provider) {
        this.provider = provider;
    }

    public SyncStatus getStatus() {
        return status;
    }

    public void setStatus(SyncStatus status) {
        this.status = status;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(Instant startedAt) {
        this.startedAt = startedAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public void setCompletedAt(Instant completedAt) {
        this.completedAt = completedAt;
    }

    public int getRecordsReceived() {
        return recordsReceived;
    }

    public void setRecordsReceived(int recordsReceived) {
        this.recordsReceived = recordsReceived;
    }

    public int getRecordsAccepted() {
        return recordsAccepted;
    }

    public void setRecordsAccepted(int recordsAccepted) {
        this.recordsAccepted = recordsAccepted;
    }

    public int getRecordsRejected() {
        return recordsRejected;
    }

    public void setRecordsRejected(int recordsRejected) {
        this.recordsRejected = recordsRejected;
    }

    public int getRetryCount() {
        return retryCount;
    }

    public void setRetryCount(int retryCount) {
        this.retryCount = retryCount;
    }

    public String getError() {
        return error;
    }

    public void setError(String error) {
        this.error = error;
    }
}
