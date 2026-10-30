package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One logged fluid intake event.
 *
 * <p>Hydration is a first-class lifestyle record rather than a generic health
 * reading: it is user-entered, frequently edited or deleted, and queried by
 * local calendar day. Storing it separately keeps the daily-total aggregation
 * exact (sum of surviving events) instead of relying on point readings that
 * cannot be corrected.</p>
 */
@Document(collection = "hydration_entries")
@CompoundIndex(name = "user_timestamp_desc", def = "{'userId': 1, 'timestamp': -1}")
@CompoundIndex(name = "user_day", def = "{'userId': 1, 'date': 1}")
public class HydrationEntry {

    @Id
    private String id;

    @Indexed
    private String userId;

    /** Calendar day in the user's timezone — the day the entry counts toward. */
    private LocalDate date;

    /** Canonical unit: millilitres. */
    private double amountMl;

    /** Instant the user drank it (or logged it, when no time was given). */
    private Instant timestamp;

    private MeasurementType source = MeasurementType.USER_ENTERED;

    private Instant createdAt;

    private Instant updatedAt;

    public HydrationEntry() {
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

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public double getAmountMl() {
        return amountMl;
    }

    public void setAmountMl(double amountMl) {
        this.amountMl = amountMl;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Instant timestamp) {
        this.timestamp = timestamp;
    }

    public MeasurementType getSource() {
        return source;
    }

    public void setSource(MeasurementType source) {
        this.source = source;
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
