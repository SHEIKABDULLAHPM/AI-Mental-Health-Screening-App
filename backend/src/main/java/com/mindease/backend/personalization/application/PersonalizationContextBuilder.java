package com.mindease.backend.personalization.application;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;

import com.mindease.backend.coach.domain.CoachMemory;
import com.mindease.backend.coach.domain.CoachMemoryRepository;
import com.mindease.backend.coach.domain.Conversation;
import com.mindease.backend.coach.domain.ConversationRepository;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.mood.application.MoodTrendAnalyzer;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteraction;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

/**
 * Centralized context builder that aggregates signals from all features
 * into a single, deterministic, privacy-safe PersonalizedContext.
 *
 * <p>This builder never sends raw private data to external services.
 * It produces structured, derived signals only.</p>
 */
@Component
public class PersonalizationContextBuilder {

    private static final Logger log = LoggerFactory.getLogger(PersonalizationContextBuilder.class);

    private static final String CONTEXT_VERSION = "personalization-ctx-v1";

    /** Time-to-live for a cached context before a refresh is needed. */
    private static final long CONTEXT_TTL_MINUTES = 30;

    /** Look-back windows. */
    private static final int MOOD_WINDOW_DAYS = 14;
    private static final int JOURNAL_WINDOW_DAYS = 30;
    private static final int INTERACTION_WINDOW_DAYS = 14;
    private static final int COACH_RECENT_CONVERSATIONS = 5;

    /** Limits. */
    private static final int MAX_RECENT_MOODS = 14;
    private static final int MAX_RECENT_JOURNALS = 10;
    private static final int MAX_COACH_MEMORIES = 10;

    private final MoodEntryRepository moodRepo;
    private final JournalEntryRepository journalRepo;
    private final RecommendationInteractionRepository interactionRepo;
    private final ConversationRepository conversationRepo;
    private final CoachMemoryRepository memoryRepo;
    private final WellnessProfileRepository wellnessRepo;
    private final MoodTrendAnalyzer moodTrendAnalyzer;

    public PersonalizationContextBuilder(
            MoodEntryRepository moodRepo,
            JournalEntryRepository journalRepo,
            RecommendationInteractionRepository interactionRepo,
            ConversationRepository conversationRepo,
            CoachMemoryRepository memoryRepo,
            WellnessProfileRepository wellnessRepo,
            MoodTrendAnalyzer moodTrendAnalyzer) {
        this.moodRepo = moodRepo;
        this.journalRepo = journalRepo;
        this.interactionRepo = interactionRepo;
        this.conversationRepo = conversationRepo;
        this.memoryRepo = memoryRepo;
        this.wellnessRepo = wellnessRepo;
        this.moodTrendAnalyzer = moodTrendAnalyzer;
    }

    /**
     * Build a fresh personalized context for the given user.
     * Each signal is individually bounded and failure-isolated.
     */
    public PersonalizedContext build(String userId) {
        PersonalizedContext ctx = new PersonalizedContext();
        ctx.setUserId(userId);
        ctx.setContextVersion(CONTEXT_VERSION);

        // Build each signal independently — failure in one does not affect others
        buildMoodContext(userId, ctx);
        buildJournalContext(userId, ctx);
        buildRecommendationContext(userId, ctx);
        buildCoachContext(userId, ctx);
        buildWellnessContext(userId, ctx);
        deriveEmotionalThemes(ctx);
        derivePersonalizationSummary(ctx);

        Instant now = Instant.now();
        ctx.setGeneratedAt(now);
        ctx.setExpiresAt(now.plus(CONTEXT_TTL_MINUTES, ChronoUnit.MINUTES));

        return ctx;
    }

    // ── Mood context ──────────────────────────────────────────────

    private void buildMoodContext(String userId, PersonalizedContext ctx) {
        try {
            List<MoodEntry> recentMoods = moodRepo.findByUserIdOrderByRecordedAtDesc(
                    userId, PageRequest.of(0, MAX_RECENT_MOODS));

            if (recentMoods.isEmpty()) {
                ctx.setMoodEntryCount(0);
                return;
            }

            ctx.setMoodEntryCount(recentMoods.size());

            // Current mood (most recent)
            MoodEntry current = recentMoods.get(0);
            ctx.setCurrentMood(current.getMood());
            ctx.setCurrentEmotion(current.getEmotion());

            // Hours since last check-in
            if (current.getRecordedAt() != null) {
                long hours = ChronoUnit.HOURS.between(current.getRecordedAt(), Instant.now());
                ctx.setHoursSinceLastCheckin(hours);
            }

            // Mood distribution
            Map<String, Long> distribution = recentMoods.stream()
                    .filter(m -> m.getMood() != null)
                    .collect(Collectors.groupingBy(MoodEntry::getMood, Collectors.counting()));
            ctx.setMoodDistribution(distribution);

            // Dominant mood
            String dominant = distribution.entrySet().stream()
                    .max(Map.Entry.comparingByValue())
                    .map(Map.Entry::getKey)
                    .orElse("neutral");
            ctx.setDominantMood(dominant);

            // Trend analysis (using last 14 days)
            Instant since = Instant.now().minus(MOOD_WINDOW_DAYS, ChronoUnit.DAYS);
            List<MoodEntry> trendEntries = moodRepo.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                    userId, since);
            Map<String, Object> trendData = moodTrendAnalyzer.analyzeTrend(trendEntries);
            ctx.setMoodTrend((String) trendData.getOrDefault("direction", "unknown"));
            ctx.setMoodTrendDescription((String) trendData.getOrDefault("description", ""));

        } catch (Exception e) {
            log.debug("Could not build mood context for personalization: {}", e.getMessage());
        }
    }

    // ── Journal context ───────────────────────────────────────────

    private void buildJournalContext(String userId, PersonalizedContext ctx) {
        try {
            List<JournalEntry> recentJournals = journalRepo.findByUserIdOrderByCreatedAtDesc(
                    userId, PageRequest.of(0, MAX_RECENT_JOURNALS));

            if (recentJournals.isEmpty()) {
                ctx.setJournalAvailable(false);
                return;
            }

            ctx.setJournalAvailable(true);
            ctx.setRecentJournalCount(recentJournals.size());

            // Extract emotional themes from AI analysis (metadata only, no raw content)
            List<String> themes = new ArrayList<>();
            List<String> sentiments = new ArrayList<>();
            for (JournalEntry journal : recentJournals) {
                if (journal.getAiAnalysis() != null) {
                    if (journal.getAiAnalysis().getEmotion() != null) {
                        themes.add(journal.getAiAnalysis().getEmotion());
                    }
                    if (journal.getAiAnalysis().getEmotionalThemes() != null) {
                        String[] themeArray = journal.getAiAnalysis().getEmotionalThemes().split(",");
                        for (String t : themeArray) {
                            String trimmed = t.trim();
                            if (!trimmed.isEmpty() && !themes.contains(trimmed)) {
                                themes.add(trimmed);
                            }
                        }
                    }
                    if (journal.getAiAnalysis().getSentiment() != null) {
                        sentiments.add(journal.getAiAnalysis().getSentiment());
                    }
                }
                // Also use user-assigned emotion
                if (journal.getEmotion() != null && !themes.contains(journal.getEmotion())) {
                    themes.add(journal.getEmotion());
                }
            }
            ctx.setJournalEmotionalThemes(themes.stream().limit(10).toList());
            ctx.setJournalSentiments(sentiments.stream().distinct().limit(5).toList());

            // Activity level based on recent journal count
            Instant thirtyDaysAgo = Instant.now().minus(JOURNAL_WINDOW_DAYS, ChronoUnit.DAYS);
            long recentCount = journalRepo.findByUserIdOrderByCreatedAtDesc(
                    userId, PageRequest.of(0, MAX_RECENT_JOURNALS)).stream()
                    .filter(j -> j.getCreatedAt() != null && j.getCreatedAt().isAfter(thirtyDaysAgo))
                    .count();
            ctx.setJournalActivityLevel(classifyActivityLevel(recentCount));

        } catch (Exception e) {
            log.debug("Could not build journal context for personalization: {}", e.getMessage());
        }
    }

    // ── Recommendation context ────────────────────────────────────

    private void buildRecommendationContext(String userId, PersonalizedContext ctx) {
        try {
            Instant since = Instant.now().minus(INTERACTION_WINDOW_DAYS, ChronoUnit.DAYS);
            List<RecommendationInteraction> recentInteractions =
                    interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(userId, since);

            if (recentInteractions.isEmpty()) {
                ctx.setRecentlyCompletedRecommendations(List.of());
                ctx.setRecentlyDismissedRecommendations(List.of());
                ctx.setRecentlyShownRecommendations(List.of());
                ctx.setHelpfulRecommendations(List.of());
                ctx.setNotUsefulRecommendations(List.of());
                return;
            }

            Map<String, List<String>> byType = recentInteractions.stream()
                    .collect(Collectors.groupingBy(
                            RecommendationInteraction::getInteractionType,
                            Collectors.mapping(
                                    RecommendationInteraction::getContentId,
                                    Collectors.toList())));

            ctx.setRecentlyCompletedRecommendations(
                    byType.getOrDefault("COMPLETED", List.of()));
            ctx.setRecentlyDismissedRecommendations(
                    byType.getOrDefault("DISMISSED", List.of()));
            ctx.setRecentlyShownRecommendations(
                    byType.getOrDefault("SHOWN", List.of()));
            ctx.setHelpfulRecommendations(
                    byType.getOrDefault("HELPFUL", List.of()));
            ctx.setNotUsefulRecommendations(
                    byType.getOrDefault("NOT_USEFUL", List.of()));

        } catch (Exception e) {
            log.debug("Could not build recommendation context for personalization: {}", e.getMessage());
        }
    }

    // ── Coach context ─────────────────────────────────────────────

    private void buildCoachContext(String userId, PersonalizedContext ctx) {
        try {
            List<Conversation> recentConversations =
                    conversationRepo.findByUserIdOrderByUpdatedAtDesc(
                            userId, PageRequest.of(0, COACH_RECENT_CONVERSATIONS));
            ctx.setCoachActive(!recentConversations.isEmpty());

            // Extract topic signals from coach memories
            List<CoachMemory> memories = memoryRepo.findByUserIdOrderByConfidenceDesc(userId);
            if (memories.isEmpty()) {
                ctx.setCoachMemoryCategories(List.of());
                ctx.setCoachTopics(List.of());
                return;
            }

            List<String> categories = memories.stream()
                    .limit(MAX_COACH_MEMORIES)
                    .map(CoachMemory::getCategory)
                    .distinct()
                    .toList();
            ctx.setCoachMemoryCategories(categories);

            // Extract topic keywords from memory content (no raw sensitive data)
            List<String> topics = new ArrayList<>();
            for (CoachMemory memory : memories) {
                if (memory.getContent() != null && memory.getContent().length() > 5) {
                    // Use category as a topic signal
                    String topic = memory.getCategory();
                    if (topic != null && !topics.contains(topic)) {
                        topics.add(topic);
                    }
                }
            }
            ctx.setCoachTopics(topics.stream().limit(5).toList());

        } catch (Exception e) {
            log.debug("Could not build coach context for personalization: {}", e.getMessage());
        }
    }

    // ── Wellness profile ──────────────────────────────────────────

    private void buildWellnessContext(String userId, PersonalizedContext ctx) {
        try {
            var profile = wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(userId);
            if (profile.isEmpty()) return;

            WellnessProfile wp = profile.get();
            if (wp.getStressLevel() != null) ctx.setStressLevel(wp.getStressLevel());
            if (wp.getSleepQuality() != null) ctx.setSleepQuality(wp.getSleepQuality());
            if (wp.getPrimaryFocus() != null) ctx.setPrimaryFocus(wp.getPrimaryFocus());
            if (wp.getWellnessScore() != null) ctx.setWellnessScore(wp.getWellnessScore());

        } catch (Exception e) {
            log.debug("Could not build wellness context for personalization: {}", e.getMessage());
        }
    }

    // ── Derived signals ───────────────────────────────────────────

    /**
     * Derive cross-feature emotional themes by combining mood and journal signals.
     * Deduplicates and prioritizes the most frequently occurring themes.
     */
    private void deriveEmotionalThemes(PersonalizedContext ctx) {
        Map<String, Integer> themeCounts = new LinkedHashMap<>();

        // Mood-based themes
        if (ctx.getCurrentMood() != null) {
            themeCounts.merge(ctx.getCurrentMood(), 3, Integer::sum);
        }
        if (ctx.getCurrentEmotion() != null) {
            themeCounts.merge(ctx.getCurrentEmotion(), 2, Integer::sum);
        }
        if (ctx.getMoodDistribution() != null) {
            for (var entry : ctx.getMoodDistribution().entrySet()) {
                themeCounts.merge(entry.getKey(), (int) Math.min(entry.getValue(), 5), Integer::sum);
            }
        }

        // Journal-based themes
        if (ctx.getJournalEmotionalThemes() != null) {
            for (String theme : ctx.getJournalEmotionalThemes()) {
                themeCounts.merge(theme, 2, Integer::sum);
            }
        }

        // Coach topics
        if (ctx.getCoachTopics() != null) {
            for (String topic : ctx.getCoachTopics()) {
                themeCounts.merge(topic, 1, Integer::sum);
            }
        }

        // Sort by frequency, take top themes
        List<String> sortedThemes = themeCounts.entrySet().stream()
                .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
                .limit(8)
                .map(Map.Entry::getKey)
                .toList();

        ctx.setEmotionalThemes(sortedThemes);

        // Preference signals
        Map<String, String> preferences = new HashMap<>();
        if (ctx.getPrimaryFocus() != null) {
            preferences.put("wellnessFocus", ctx.getPrimaryFocus());
        }
        if (ctx.getDominantMood() != null) {
            preferences.put("dominantMood", ctx.getDominantMood());
        }
        if (ctx.getStressLevel() != null) {
            preferences.put("stressLevel", ctx.getStressLevel());
        }
        ctx.setPreferenceSignals(preferences);
    }

    /**
     * Generate an explainable, user-facing personalization summary.
     * Never exposes internal scores or system details.
     */
    private void derivePersonalizationSummary(PersonalizedContext ctx) {
        StringBuilder summary = new StringBuilder();

        // Mood-based summary
        if (ctx.getMoodTrend() != null) {
            switch (ctx.getMoodTrend()) {
                case "improving" -> summary.append("Your mood has been trending positively recently. ");
                case "declining" -> summary.append("Your mood has been trending downward recently. ");
                case "stable" -> summary.append("Your mood has been fairly consistent. ");
                case "fluctuating" -> summary.append("Your mood has been varying recently. ");
            }
        }

        // Journal activity summary
        if (ctx.isJournalAvailable()) {
            String level = ctx.getJournalActivityLevel();
            if ("active".equals(level)) {
                summary.append("You've been writing regularly in your journal. ");
            } else if ("moderate".equals(level)) {
                summary.append("You've been reflecting in your journal. ");
            }
        }

        // Recommendation engagement
        int completedCount = ctx.getRecentlyCompletedRecommendations() != null
                ? ctx.getRecentlyCompletedRecommendations().size() : 0;
        if (completedCount > 0) {
            summary.append("You've completed ").append(completedCount)
                    .append(" wellness activities recently. ");
        }

        // Coach engagement
        if (ctx.isCoachActive()) {
            summary.append("You've been exploring your wellness with the AI Coach. ");
        }

        if (summary.isEmpty()) {
            summary.append("Start tracking your mood to unlock personalized insights.");
        }

        ctx.setPersonalizationSummary(summary.toString().trim());
    }

    // ── Helpers ───────────────────────────────────────────────────

    private String classifyActivityLevel(long entriesInWindow) {
        if (entriesInWindow >= 10) return "very_active";
        if (entriesInWindow >= 5) return "active";
        if (entriesInWindow >= 2) return "moderate";
        if (entriesInWindow >= 1) return "occasional";
        return "inactive";
    }
}
