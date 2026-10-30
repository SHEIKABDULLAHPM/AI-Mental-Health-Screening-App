package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A single normalized, provider-independent health measurement.
 *
 * <p>{@code date} is the calendar day (in the user's timezone) the reading
 * belongs to; it is stored alongside the instant so daily/weekly queries never
 * need to recompute timezones. The unique index on
 * {@code (userId, deviceId, metricType, timestamp)} is the duplicate-prevention
 * gate: replayed BLE packets or re-syncs collapse onto the same document.</p>
 */
@Document(collection = "health_readings")
@CompoundIndex(name = "uq_reading",
        def = "{'userId': 1, 'deviceId': 1, 'metricType': 1, 'timestamp': 1}", unique = true)
@CompoundIndex(name = "user_metric_time",
        def = "{'userId': 1, 'metricType': 1, 'timestamp': -1}")
@CompoundIndex(name = "user_date_metric",
        def = "{'userId': 1, 'date': 1, 'metricType': 1}")
public class HealthReading {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String deviceId;

    private WearableProvider source;

    private HealthMetricType metricType;

    /** Value expressed in the metric's canonical unit. */
    private double value;

    private String unit;

    private Instant timestamp;

    /** Calendar day of {@code timestamp} in the user's timezone. */
    @Indexed
    private LocalDate date;

    private Instant recordedAt;

    private MeasurementType measurementType;

    public HealthReading() {
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

    public HealthMetricType getMetricType() {
        return metricType;
    }

    public void setMetricType(HealthMetricType metricType) {
        this.metricType = metricType;
    }

    public double getValue() {
        return value;
    }

    public void setValue(double value) {
        this.value = value;
    }

    public String getUnit() {
        return unit;
    }

    public void setUnit(String unit) {
        this.unit = unit;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }

    public void setRecordedAt(Instant recordedAt) {
        this.recordedAt = recordedAt;
    }

    public MeasurementType getMeasurementType() {
        return measurementType;
    }

    public void setMeasurementType(MeasurementType measurementType) {
        this.measurementType = measurementType;
    }
}
