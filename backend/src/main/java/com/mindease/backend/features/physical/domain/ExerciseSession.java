package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One exercise/activity session recorded by a wearable.
 *
 * <p>Every measurement field is optional and stays {@code null} when the
 * device does not expose it — nothing is invented.</p>
 */
@Document(collection = "exercise_sessions")
@CompoundIndex(name = "uq_user_device_start",
        def = "{'userId': 1, 'deviceId': 1, 'startTime': 1}", unique = true)
@CompoundIndex(name = "user_start_desc", def = "{'userId': 1, 'startTime': -1}")
public class ExerciseSession {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String deviceId;

    private WearableProvider source;

    /** Exercise type only when reliably identified (e.g. WALKING, RUNNING). */
    private String type;

    private Instant startTime;

    private Instant endTime;

    private Long durationMillis;

    private LocalDate date;

    /** Canonical unit: meters. */
    private Double distanceMeters;

    /** Canonical unit: kcal. */
    private Double caloriesKcal;

    private Double averageHeartRate;

    private Double maximumHeartRate;

    private Instant recordedAt;

    public ExerciseSession() {
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

    public WearableProvider getSource() {
        return source;
    }

    public void setSource(WearableProvider source) {
        this.source = source;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public Instant getStartTime() {
        return startTime;
    }

    public void setStartTime(Instant startTime) {
        this.startTime = startTime;
    }

    public Instant getEndTime() {
        return endTime;
    }

    public void setEndTime(Instant endTime) {
        this.endTime = endTime;
    }

    public Long getDurationMillis() {
        return durationMillis;
    }

    public void setDurationMillis(Long durationMillis) {
        this.durationMillis = durationMillis;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public Double getDistanceMeters() {
        return distanceMeters;
    }

    public void setDistanceMeters(Double distanceMeters) {
        this.distanceMeters = distanceMeters;
    }

    public Double getCaloriesKcal() {
        return caloriesKcal;
    }

    public void setCaloriesKcal(Double caloriesKcal) {
        this.caloriesKcal = caloriesKcal;
    }

    public Double getAverageHeartRate() {
        return averageHeartRate;
    }

    public void setAverageHeartRate(Double averageHeartRate) {
        this.averageHeartRate = averageHeartRate;
    }

    public Double getMaximumHeartRate() {
        return maximumHeartRate;
    }

    public void setMaximumHeartRate(Double maximumHeartRate) {
        this.maximumHeartRate = maximumHeartRate;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }

    public void setRecordedAt(Instant recordedAt) {
        this.recordedAt = recordedAt;
    }
}
