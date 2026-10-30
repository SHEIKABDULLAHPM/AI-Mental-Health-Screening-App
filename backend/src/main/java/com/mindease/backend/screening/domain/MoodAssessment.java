package com.mindease.backend.screening.domain;

/**
 * Onboarding mood assessment snapshot embedded in a {@link Screening}.
 *
 * <p>Stores only user-provided onboarding context. The authoritative mood
 * history stays in {@code mood_entries}; AI-derived signals stay on the linked
 * mood entry's {@code aiObservations}. This object never duplicates trend or
 * scoring calculations — those are derived server-side via
 * {@code MoodTrendAnalyzer} / {@code MoodService}.</p>
 */
public class MoodAssessment {

    /** User-reported current mood id (very_happy|happy|calm|okay|low|stressed). */
    private String currentMood;

    /** Optional emotion tag chosen by the user (e.g. Grateful, Anxious). */
    private String emotion;

    /** Optional self-reported intensity 1-10. */
    private Integer intensity;

    /** Optional short reflection / note (max 5000 chars, same as mood entries). */
    private String note;

    /** How often the user experiences their recent mood pattern (free label). */
    private String frequency;

    /** Recent emotional change label (e.g. BETTER/SAME/WORSE/FLUCTUATING). */
    private String recentChange;

    /** Optional mood context label (e.g. work, sleep, relationships). */
    private String context;

    /**
     * Id of the canonical {@code mood_entries} document created for this
     * onboarding check-in, if the client persisted one. Used for traceability
     * only — ownership is always re-validated server-side.
     */
    private String linkedMoodEntryId;

    public MoodAssessment() {
    }

    public String getCurrentMood() {
        return currentMood;
    }

    public void setCurrentMood(String currentMood) {
        this.currentMood = currentMood;
    }

    public String getEmotion() {
        return emotion;
    }

    public void setEmotion(String emotion) {
        this.emotion = emotion;
    }

    public Integer getIntensity() {
        return intensity;
    }

    public void setIntensity(Integer intensity) {
        this.intensity = intensity;
    }

    public String getNote() {
        return note;
    }

    public void setNote(String note) {
        this.note = note;
    }

    public String getFrequency() {
        return frequency;
    }

    public void setFrequency(String frequency) {
        this.frequency = frequency;
    }

    public String getRecentChange() {
        return recentChange;
    }

    public void setRecentChange(String recentChange) {
        this.recentChange = recentChange;
    }

    public String getContext() {
        return context;
    }

    public void setContext(String context) {
        this.context = context;
    }

    public String getLinkedMoodEntryId() {
        return linkedMoodEntryId;
    }

    public void setLinkedMoodEntryId(String linkedMoodEntryId) {
        this.linkedMoodEntryId = linkedMoodEntryId;
    }
}
