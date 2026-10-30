package com.mindease.backend.ai.domain;

/**
 * Deterministic wellness analysis snapshot attached to an AI job. This is the
 * minimal, already-anonymized input the AI service may use - raw assessment
 * answers are never sent to the LLM.
 */
public class DeterministicScores {

    private Integer phq9;
    private Integer gad7;
    private Integer pss10;
    private Integer who5;
    private Integer wellnessScore;
    private String stressLevel;
    private Integer lifestyleScore;
    private String sleepQuality;
    private String primaryFocus;

    // ── Onboarding mood context (all optional, validated structured input) ──
    // User-reported mood stays the primary signal; trend/history are
    // deterministic server-side derivations, never client calculations.

    /** Self-reported onboarding mood id, if provided. */
    private String onboardingMood;

    /** Deterministic 1-6 mood value derived from onboardingMood. */
    private Integer onboardingMoodScore;

    /** Optional user-reported emotion tag from onboarding. */
    private String onboardingMoodEmotion;

    /** Optional user-reported intensity 1-10 from onboarding. */
    private Integer onboardingMoodIntensity;

    /** Deterministic trend direction from mood history (or "unknown"). */
    private String moodTrendDirection;

    /** Human-readable trend description (or insufficiency notice). */
    private String moodTrendDescription;

    /** Number of historical mood entries available at submit time. */
    private Integer moodHistoryCount;

    // ── Camera supporting signal (all optional; absent = skipped/unclear) ──
    // Extracted server-side from the linked mood entry's CAMERA AI
    // observation — never trusted from raw client fields.

    /** Stable camera-detected canonical emotion (e.g. neutral, happy). */
    private String cameraEmotion;

    /** Camera confidence 0-1 from the fusion result. */
    private Double cameraConfidence;

    /** Model version that produced the camera signal. */
    private String cameraModelVersion;

    /** Deterministic verdict: agree|close|differs|noSignal. */
    private String signalAgreement;

    public DeterministicScores() {
    }

    public Integer getPhq9() {
        return phq9;
    }

    public void setPhq9(Integer phq9) {
        this.phq9 = phq9;
    }

    public Integer getGad7() {
        return gad7;
    }

    public void setGad7(Integer gad7) {
        this.gad7 = gad7;
    }

    public Integer getPss10() {
        return pss10;
    }

    public void setPss10(Integer pss10) {
        this.pss10 = pss10;
    }

    public Integer getWho5() {
        return who5;
    }

    public void setWho5(Integer who5) {
        this.who5 = who5;
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

    public String getOnboardingMood() {
        return onboardingMood;
    }

    public void setOnboardingMood(String onboardingMood) {
        this.onboardingMood = onboardingMood;
    }

    public Integer getOnboardingMoodScore() {
        return onboardingMoodScore;
    }

    public void setOnboardingMoodScore(Integer onboardingMoodScore) {
        this.onboardingMoodScore = onboardingMoodScore;
    }

    public String getOnboardingMoodEmotion() {
        return onboardingMoodEmotion;
    }

    public void setOnboardingMoodEmotion(String onboardingMoodEmotion) {
        this.onboardingMoodEmotion = onboardingMoodEmotion;
    }

    public Integer getOnboardingMoodIntensity() {
        return onboardingMoodIntensity;
    }

    public void setOnboardingMoodIntensity(Integer onboardingMoodIntensity) {
        this.onboardingMoodIntensity = onboardingMoodIntensity;
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

    public String getCameraModelVersion() {
        return cameraModelVersion;
    }

    public void setCameraModelVersion(String cameraModelVersion) {
        this.cameraModelVersion = cameraModelVersion;
    }

    public String getSignalAgreement() {
        return signalAgreement;
    }

    public void setSignalAgreement(String signalAgreement) {
        this.signalAgreement = signalAgreement;
    }
}
