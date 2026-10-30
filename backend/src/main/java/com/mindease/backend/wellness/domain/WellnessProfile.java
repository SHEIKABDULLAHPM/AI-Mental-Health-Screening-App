package com.mindease.backend.wellness.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Wellness profile backing the Flutter profile/dashboard screens.
 *
 * <p>AI-derived values (score, stress level, insight, focus) remain null and
 * the status stays {@code AI_ANALYSIS_PENDING} until the future AI service
 * completes analysis. No fake values are ever generated at this stage.</p>
 */
@Document(collection = "wellness_profiles")
@CompoundIndexes({
    @CompoundIndex(name = "uq_user_assessment", def = "{'userId': 1, 'assessmentId': 1}", unique = true)
})
public class WellnessProfile {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String tenantId = "app";

    @Indexed
    private String assessmentId;

    private ProfileStatus status = ProfileStatus.AI_ANALYSIS_PENDING;

    private Integer wellnessScore;

    private String stressLevel;

    private Integer lifestyleScore;

    private String sleepQuality;

    private String primaryFocus;

    private String aiInsight;

    /**
     * Safety escalation flag derived from PHQ-9 item 9 (self-harm ideation).
     * True when the stored answer is greater than zero. This is never exposed
     * as a diagnosis - it only unlocks an explicit support/help affordance.
     */
    private Boolean safetyFlag;

    // ── Integrated Mood Check-In summary (all nullable for backward compat) ──
    // user-provided: moodMood/moodEmotion/moodIntensity (copied from screening)
    // calculated:    moodScore/moodTrendDirection/moodTrendDescription/moodHistoryCount
    // AI-derived:    aiInsight (now mood-aware, still stored in aiInsight)

    /** Self-reported onboarding mood id. */
    private String moodMood;

    /** Self-reported onboarding emotion tag. */
    private String moodEmotion;

    /** Self-reported onboarding intensity 1-10. */
    private Integer moodIntensity;

    /** Deterministic 1-6 mood value derived from moodMood. */
    private Integer moodScore;

    /** Deterministic mood trend direction (or "unknown"). */
    private String moodTrendDirection;

    /** Human-readable mood trend description. */
    private String moodTrendDescription;

    /** Historical mood entry count at assessment time. */
    private Integer moodHistoryCount;

    // ── Camera supporting signal (all nullable; absent = skipped/unclear) ──
    // The model/version that produced the signal is preserved on the linked
    // mood entry's aiObservations + emotion event; the profile keeps only the
    // interpretation-relevant subset for the insight and dashboard.

    /** Stable camera-detected canonical emotion (e.g. neutral, happy). */
    private String cameraEmotion;

    /** Camera confidence 0-1 from the fusion result. */
    private Double cameraConfidence;

    /** Deterministic verdict: agree|close|differs|noSignal. */
    private String signalAgreement;

    private Instant createdAt;

    private Instant updatedAt;

    public WellnessProfile() {
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

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public String getAssessmentId() {
        return assessmentId;
    }

    public void setAssessmentId(String assessmentId) {
        this.assessmentId = assessmentId;
    }

    public ProfileStatus getStatus() {
        return status;
    }

    public void setStatus(ProfileStatus status) {
        this.status = status;
    }

    public Integer getWellnessScore() {
        return wellnessScore;
    }

    public void setWellnessScore(Integer wellnessScore) {
        this.wellnessScore = wellnessScore;
    }

    public String getStressLevel() {
        return stressLevel;
    }

    public void setStressLevel(String stressLevel) {
        this.stressLevel = stressLevel;
    }

    public Integer getLifestyleScore() {
        return lifestyleScore;
    }

    public void setLifestyleScore(Integer lifestyleScore) {
        this.lifestyleScore = lifestyleScore;
    }

    public String getSleepQuality() {
        return sleepQuality;
    }

    public void setSleepQuality(String sleepQuality) {
        this.sleepQuality = sleepQuality;
    }

    public String getPrimaryFocus() {
        return primaryFocus;
    }

    public void setPrimaryFocus(String primaryFocus) {
        this.primaryFocus = primaryFocus;
    }

    public String getAiInsight() {
        return aiInsight;
    }

    public void setAiInsight(String aiInsight) {
        this.aiInsight = aiInsight;
    }

    public Boolean getSafetyFlag() {
        return safetyFlag;
    }

    public void setSafetyFlag(Boolean safetyFlag) {
        this.safetyFlag = safetyFlag;
    }

    public String getMoodMood() {
        return moodMood;
    }

    public void setMoodMood(String moodMood) {
        this.moodMood = moodMood;
    }

    public String getMoodEmotion() {
        return moodEmotion;
    }

    public void setMoodEmotion(String moodEmotion) {
        this.moodEmotion = moodEmotion;
    }

    public Integer getMoodIntensity() {
        return moodIntensity;
    }

    public void setMoodIntensity(Integer moodIntensity) {
        this.moodIntensity = moodIntensity;
    }

    public Integer getMoodScore() {
        return moodScore;
    }

    public void setMoodScore(Integer moodScore) {
        this.moodScore = moodScore;
    }

    public String getMoodTrendDirection() {
        return moodTrendDirection;
    }

    public void setMoodTrendDirection(String moodTrendDirection) {
        this.moodTrendDirection = moodTrendDirection;
    }

    public String getMoodTrendDescription() {
        return moodTrendDescription;
    }

    public void setMoodTrendDescription(String moodTrendDescription) {
        this.moodTrendDescription = moodTrendDescription;
    }

    public Integer getMoodHistoryCount() {
        return moodHistoryCount;
    }

    public void setMoodHistoryCount(Integer moodHistoryCount) {
        this.moodHistoryCount = moodHistoryCount;
    }

    public String getCameraEmotion() {
        return cameraEmotion;
    }

    public void setCameraEmotion(String cameraEmotion) {
        this.cameraEmotion = cameraEmotion;
    }

    public Double getCameraConfidence() {
        return cameraConfidence;
    }

    public void setCameraConfidence(Double cameraConfidence) {
        this.cameraConfidence = cameraConfidence;
    }

    public String getSignalAgreement() {
        return signalAgreement;
    }

    public void setSignalAgreement(String signalAgreement) {
        this.signalAgreement = signalAgreement;
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