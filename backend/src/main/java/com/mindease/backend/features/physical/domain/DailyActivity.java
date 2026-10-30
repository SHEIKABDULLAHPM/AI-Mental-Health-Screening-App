package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Aggregated activity for one user and one local calendar day.
 *
 * <p>{@code steps}/{@code distanceMeters}/{@code caloriesKcal} are device daily
 * totals when the device exposes cumulative daily data, otherwise the sum of
 * interval readings accepted for that day. {@code null} means "no data
 * received" — it is never replaced with a fabricated zero.</p>
 */
@Document(collection = "daily_activity")
@CompoundIndex(name = "uq_user_day", def = "{'userId': 1, 'date': 1}", unique = true)
@CompoundIndex(name = "user_date_desc", def = "{'userId': 1, 'date': -1}")
public class DailyActivity {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String deviceId;

    private WearableProvider source;

    private LocalDate date;

    private Integer steps;

    /** Canonical unit: meters. */
    private Double distanceMeters;

    /** Canonical unit: kcal. */
    private Double caloriesKcal;

    private Integer activeMinutes;

    private Instant createdAt;

    private Instant updatedAt;

    public DailyActivity() {
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

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public Integer getSteps() {
        return steps;
    }

    public void setSteps(Integer steps) {
        this.steps = steps;
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

    public Integer getActiveMinutes() {
        return activeMinutes;
    }

    public void setActiveMinutes(Integer activeMinutes) {
        this.activeMinutes = activeMinutes;
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
}
