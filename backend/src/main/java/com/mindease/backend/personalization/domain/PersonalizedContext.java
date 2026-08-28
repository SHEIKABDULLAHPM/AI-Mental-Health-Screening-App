package com.mindease.backend.personalization.domain;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Cached personalized context for a single user.
 *
 * <p>Stores only derived signals — never duplicates raw journal entries,
 * mood records, or coach conversations. Source-of-truth data remains
 * in the feature-specific collections.</p>
 *
 * <p>This document is rebuilt on-demand (or on explicit refresh) and
 * used by all features that need cross-feature context.</p>
 */
@Document(collection = "personalized_contexts")
@CompoundIndex(name = "userId_version_idx", def = "{'userId': 1, 'contextVersion': -1}")
public class PersonalizedContext {

    @Id
    private String id;

    @Indexed
    private String userId;

    // ── Mood context ──────────────────────────────────────────────

    /** Current mood label (e.g. "happy", "stressed", "low"). */
    private String currentMood;

    /** Current emotion label. */
    private String currentEmotion;

    /** Trend direction: improving, declining, stable, fluctuating, unknown. */
    private String moodTrend;

    /** Human-readable mood trend description. */
    private String moodTrendDescription;

    /** Recent mood distribution over the analysis window. */
    private Map<String, Long> moodDistribution;

    /** Number of mood entries in the analysis window. */
    private int moodEntryCount;

    /** Hours since the last mood check-in. */
    private long hoursSinceLastCheckin;

    /** Dominant mood in the recent window. */
    private String dominantMood;

    // ── Journal context ───────────────────────────────────────────

    /** Whether journal data is available for this user. */
    private boolean journalAvailable;

    /** Emotional themes derived from journal AI analysis (metadata only). */
    private List<String> journalEmotionalThemes;

    /** Journal-derived sentiment summary. */
    private List<String> journalSentiments;

    /** Number of recent journal entries considered. */
    private int recentJournalCount;

    /** Journal writing frequency indicator. */
    private String journalActivityLevel;

    // ── Recommendation context ────────────────────────────────────

    /** Content IDs recently completed by the user. */
    private List<String> recentlyCompletedRecommendations;

    /** Content IDs recently dismissed by the user. */
    private List<String> recentlyDismissedRecommendations;

    /** Content IDs recently shown to the user. */
    private List<String> recentlyShownRecommendations;

    /** Content IDs the user rated as helpful. */
    private List<String> helpfulRecommendations;

    /** Content IDs the user rated as not useful. */
    private List<String> notUsefulRecommendations;

    // ── Coach context ─────────────────────────────────────────────

    /** Whether the user has active coach conversations. */
    private boolean coachActive;

    /** Topics or themes from recent coach conversations (metadata only). */
    private List<String> coachTopics;

    /** Coach memory categories for this user. */
    private List<String> coachMemoryCategories;

    // ── Wellness profile ──────────────────────────────────────────

    /** User's reported stress level. */
    private String stressLevel;

    /** User's reported sleep quality. */
    private String sleepQuality;

    /** User's primary wellness focus. */
    private String primaryFocus;

    /** User's wellness score (0–100). */
    private Integer wellnessScore;

    // ── Derived signals ───────────────────────────────────────────

    /** Emotional themes derived across all features. */
    private List<String> emotionalThemes;

    /** User preference signals derived from interactions. */
    private Map<String, String> preferenceSignals;

    /** Short explainable reason for the current personalization state. */
    private String personalizationSummary;

    // ── Metadata ──────────────────────────────────────────────────

    /** Context schema version. */
    private String contextVersion;

    /** When this context was generated. */
    private Instant generatedAt;

    /** When this context expires (stale after this time). */
    private Instant expiresAt;

    @Version
    private Long documentVersion;

    public PersonalizedContext() {}

    // ── Getters & Setters ─────────────────────────────────────────

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getCurrentMood() { return currentMood; }
    public void setCurrentMood(String currentMood) { this.currentMood = currentMood; }

    public String getCurrentEmotion() { return currentEmotion; }
    public void setCurrentEmotion(String currentEmotion) { this.currentEmotion = currentEmotion; }

    public String getMoodTrend() { return moodTrend; }
    public void setMoodTrend(String moodTrend) { this.moodTrend = moodTrend; }

    public String getMoodTrendDescription() { return moodTrendDescription; }
    public void setMoodTrendDescription(String moodTrendDescription) { this.moodTrendDescription = moodTrendDescription; }

    public Map<String, Long> getMoodDistribution() { return moodDistribution; }
    public void setMoodDistribution(Map<String, Long> moodDistribution) { this.moodDistribution = moodDistribution; }

    public int getMoodEntryCount() { return moodEntryCount; }
    public void setMoodEntryCount(int moodEntryCount) { this.moodEntryCount = moodEntryCount; }

    public long getHoursSinceLastCheckin() { return hoursSinceLastCheckin; }
    public void setHoursSinceLastCheckin(long hoursSinceLastCheckin) { this.hoursSinceLastCheckin = hoursSinceLastCheckin; }

    public String getDominantMood() { return dominantMood; }
    public void setDominantMood(String dominantMood) { this.dominantMood = dominantMood; }

    public boolean isJournalAvailable() { return journalAvailable; }
    public void setJournalAvailable(boolean journalAvailable) { this.journalAvailable = journalAvailable; }

    public List<String> getJournalEmotionalThemes() { return journalEmotionalThemes; }
    public void setJournalEmotionalThemes(List<String> journalEmotionalThemes) { this.journalEmotionalThemes = journalEmotionalThemes; }

    public List<String> getJournalSentiments() { return journalSentiments; }
    public void setJournalSentiments(List<String> journalSentiments) { this.journalSentiments = journalSentiments; }

    public int getRecentJournalCount() { return recentJournalCount; }
    public void setRecentJournalCount(int recentJournalCount) { this.recentJournalCount = recentJournalCount; }

    public String getJournalActivityLevel() { return journalActivityLevel; }
    public void setJournalActivityLevel(String journalActivityLevel) { this.journalActivityLevel = journalActivityLevel; }

    public List<String> getRecentlyCompletedRecommendations() { return recentlyCompletedRecommendations; }
    public void setRecentlyCompletedRecommendations(List<String> recentlyCompletedRecommendations) { this.recentlyCompletedRecommendations = recentlyCompletedRecommendations; }

    public List<String> getRecentlyDismissedRecommendations() { return recentlyDismissedRecommendations; }
    public void setRecentlyDismissedRecommendations(List<String> recentlyDismissedRecommendations) { this.recentlyDismissedRecommendations = recentlyDismissedRecommendations; }

    public List<String> getRecentlyShownRecommendations() { return recentlyShownRecommendations; }
    public void setRecentlyShownRecommendations(List<String> recentlyShownRecommendations) { this.recentlyShownRecommendations = recentlyShownRecommendations; }

    public List<String> getHelpfulRecommendations() { return helpfulRecommendations; }
    public void setHelpfulRecommendations(List<String> helpfulRecommendations) { this.helpfulRecommendations = helpfulRecommendations; }

    public List<String> getNotUsefulRecommendations() { return notUsefulRecommendations; }
    public void setNotUsefulRecommendations(List<String> notUsefulRecommendations) { this.notUsefulRecommendations = notUsefulRecommendations; }

    public boolean isCoachActive() { return coachActive; }
    public void setCoachActive(boolean coachActive) { this.coachActive = coachActive; }

    public List<String> getCoachTopics() { return coachTopics; }
    public void setCoachTopics(List<String> coachTopics) { this.coachTopics = coachTopics; }

    public List<String> getCoachMemoryCategories() { return coachMemoryCategories; }
    public void setCoachMemoryCategories(List<String> coachMemoryCategories) { this.coachMemoryCategories = coachMemoryCategories; }

    public String getStressLevel() { return stressLevel; }
    public void setStressLevel(String stressLevel) { this.stressLevel = stressLevel; }

    public String getSleepQuality() { return sleepQuality; }
    public void setSleepQuality(String sleepQuality) { this.sleepQuality = sleepQuality; }

    public String getPrimaryFocus() { return primaryFocus; }
    public void setPrimaryFocus(String primaryFocus) { this.primaryFocus = primaryFocus; }

    public Integer getWellnessScore() { return wellnessScore; }
    public void setWellnessScore(Integer wellnessScore) { this.wellnessScore = wellnessScore; }

    public List<String> getEmotionalThemes() { return emotionalThemes; }
    public void setEmotionalThemes(List<String> emotionalThemes) { this.emotionalThemes = emotionalThemes; }

    public Map<String, String> getPreferenceSignals() { return preferenceSignals; }
    public void setPreferenceSignals(Map<String, String> preferenceSignals) { this.preferenceSignals = preferenceSignals; }

    public String getPersonalizationSummary() { return personalizationSummary; }
    public void setPersonalizationSummary(String personalizationSummary) { this.personalizationSummary = personalizationSummary; }

    public String getContextVersion() { return contextVersion; }
    public void setContextVersion(String contextVersion) { this.contextVersion = contextVersion; }

    public Instant getGeneratedAt() { return generatedAt; }
    public void setGeneratedAt(Instant generatedAt) { this.generatedAt = generatedAt; }

    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }

    /** Check if this context has expired and should be refreshed. */
    public boolean isExpired() {
        return expiresAt != null && Instant.now().isAfter(expiresAt);
    }
}
