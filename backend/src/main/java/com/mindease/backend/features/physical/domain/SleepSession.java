package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One sleep period recorded by a wearable.
 *
 * <p>{@code sleepStages} stays {@code null} unless the device genuinely exposes
 * stage data for the target firmware — stages are never fabricated.</p>
 */
@Document(collection = "sleep_sessions")
@CompoundIndex(name = "uq_user_device_start",
        def = "{'userId': 1, 'deviceId': 1, 'startTime': 1}", unique = true)
@CompoundIndex(name = "user_start_desc", def = "{'userId': 1, 'startTime': -1}")
public class SleepSession {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String deviceId;

    private WearableProvider source;

    private Instant startTime;

    private Instant endTime;

    private Long durationMillis;

    /** Local calendar day the sleep session is attributed to (wake day). */
    @Indexed
    private LocalDate date;

    /** Optional stage breakdown — only populated when verified on-device. */
    private List<SleepStage> sleepStages;

    /**
     * Source-native stage durations in minutes, keyed by the label the source
     * actually reported (canonical {@code AWAKE/LIGHT/DEEP/REM} when the
     * provider maps them, otherwise the raw provider code such as
     * {@code RAW_0}). Never inferred from total duration.
     */
    private java.util.Map<String, Integer> stageMinutes;

    /** Where {@link #stageMinutes} came from (e.g. {@code FITPRO_RAW}). */
    private String stageSource;

    private Instant recordedAt;

    public SleepSession() {
    }

    /** A single sleep stage segment. Only used when the device reports stages. */
    public record SleepStage(String stage, Instant startTime, Instant endTime) {
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

    public List<SleepStage> getSleepStages() {
        return sleepStages;
    }

    public void setSleepStages(List<SleepStage> sleepStages) {
        this.sleepStages = sleepStages;
    }

    public java.util.Map<String, Integer> getStageMinutes() {
        return stageMinutes;
    }

    public void setStageMinutes(java.util.Map<String, Integer> stageMinutes) {
        this.stageMinutes = stageMinutes;
    }

    public String getStageSource() {
        return stageSource;
    }

    public void setStageSource(String stageSource) {
        this.stageSource = stageSource;
    }

    public Instant getRecordedAt() {
        return recordedAt;
    }

    public void setRecordedAt(Instant recordedAt) {
        this.recordedAt = recordedAt;
    }
}
