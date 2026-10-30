package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One body measurement (weight and optional height) supplied by the user or a
 * verified external scale.
 *
 * <p>Only fields that were genuinely measured are stored. Body-fat percentage,
 * muscle mass and similar composition values are never derived from weight —
 * if a source cannot measure them they simply stay {@code null}.</p>
 */
@Document(collection = "body_measurements")
@CompoundIndex(name = "user_measured_desc", def = "{'userId': 1, 'measuredAt': -1}")
public class BodyMeasurement {

    @Id
    private String id;

    @Indexed
    private String userId;

    /** Canonical unit: kilograms. */
    private Double weightKg;

    /** Canonical unit: centimetres. */
    private Double heightCm;

    /** Local day the measurement belongs to. */
    private LocalDate date;

    private Instant measuredAt;

    private MeasurementType source = MeasurementType.USER_ENTERED;

    private String deviceId;

    private Instant createdAt;

    private Instant updatedAt;

    public BodyMeasurement() {
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

    public Double getWeightKg() {
        return weightKg;
    }

    public void setWeightKg(Double weightKg) {
        this.weightKg = weightKg;
    }

    public Double getHeightCm() {
        return heightCm;
    }

    public void setHeightCm(Double heightCm) {
        this.heightCm = heightCm;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public Instant getMeasuredAt() {
        return measuredAt;
    }

    public void setMeasuredAt(Instant measuredAt) {
        this.measuredAt = measuredAt;
    }

    public MeasurementType getSource() {
        return source;
    }

    public void setSource(MeasurementType source) {
        this.source = source;
    }

    public String getDeviceId() {
        return deviceId;
    }

    public void setDeviceId(String deviceId) {
        this.deviceId = deviceId;
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
