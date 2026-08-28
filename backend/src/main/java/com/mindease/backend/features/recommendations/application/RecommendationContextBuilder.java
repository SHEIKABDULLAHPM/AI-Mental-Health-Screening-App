package com.mindease.backend.features.recommendations.application;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;

import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteraction;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

/**
 * Builds a safe, normalized context snapshot for recommendation generation.
 * Uses only structured signals — never raw private content.
 */
@Component
public class RecommendationContextBuilder {

    private static final Logger log = LoggerFactory.getLogger(RecommendationContextBuilder.class);

    private final MoodEntryRepository moodRepo;
    private final JournalEntryRepository journalRepo;
    private final WellnessProfileRepository wellnessRepo;
    private final RecommendationInteractionRepository interactionRepo;
    private final PersonalizationService personalizationService;

    public RecommendationContextBuilder(
            MoodEntryRepository moodRepo,
            JournalEntryRepository journalRepo,
            WellnessProfileRepository wellnessRepo,
            RecommendationInteractionRepository interactionRepo,
            PersonalizationService personalizationService) {
        this.moodRepo = moodRepo;
        this.journalRepo = journalRepo;
        this.wellnessRepo = wellnessRepo;
        this.interactionRepo = interactionRepo;
        this.personalizationService = personalizationService;
    }

    /**
     * Build the recommendation context for a user.
     * Returns a map of signal types to their values.
     */
    public Map<String, Object> buildContext(String userId) {
        Map<String, Object> context = new HashMap<>();
        context.put("contextVersion", "rec-ctx-v2");
        context.put("builtAt", Instant.now().toString());

        // 1. Current mood context
        buildMoodContext(userId, context);

        // 2. Journal-derived emotional signals (metadata only, no raw content)
        buildJournalContext(userId, context);

        // 3. Wellness profile preferences
        buildWellnessContext(userId, context);

        // 4. Recent interaction history (for cooldown/repetition)
        buildInteractionContext(userId, context);

        // 5. Cross-feature personalized context
        enrichWithPersonalizedContext(userId, context);

        return context;
    }

    private void buildMoodContext(String userId, Map<String, Object> context) {
        try {
            List<MoodEntry> recentMoods = moodRepo.findByUserIdOrderByRecordedAtDesc(
                    userId, PageRequest.of(0, 14));

            if (recentMoods.isEmpty()) {
                context.put("moodAvailable", false);
                return;
            }

            context.put("moodAvailable", true);
            context.put("recentMoodCount", recentMoods.size());

            // Current mood (most recent)
            MoodEntry current = recentMoods.get(0);
            context.put("currentMood", current.getMood());
            context.put("currentEmotion", current.getEmotion());

            // Mood trend: count of each mood in last 14 days
            Map<String, Long> moodDistribution = recentMoods.stream()
                    .filter(m -> m.getMood() != null)
                    .collect(Collectors.groupingBy(MoodEntry::getMood, Collectors.counting()));
            context.put("moodDistribution", moodDistribution);

            // Identify dominant mood
            String dominantMood = moodDistribution.entrySet().stream()
                    .max(Map.Entry.comparingByValue())
                    .map(Map.Entry::getKey)
                    .orElse("neutral");
            context.put("dominantMood", dominantMood);

            // Mood volatility: how many different moods in last 14 days
            context.put("moodVolatility", moodDistribution.size());

            // Time since last check-in
            long hoursSinceLastCheckin = ChronoUnit.HOURS.between(
                    current.getRecordedAt(), Instant.now());
            context.put("hoursSinceLastCheckin", hoursSinceLastCheckin);

        } catch (Exception e) {
            log.debug("Could not build mood context: {}", e.getMessage());
            context.put("moodAvailable", false);
        }
    }

    private void buildJournalContext(String userId, Map<String, Object> context) {
        try {
            List<JournalEntry> recentJournals = journalRepo.findByUserIdOrderByCreatedAtDesc(
                    userId, PageRequest.of(0, 5));

            if (recentJournals.isEmpty()) {
                context.put("journalAvailable", false);
                return;
            }

            context.put("journalAvailable", true);
            context.put("recentJournalCount", recentJournals.size());

            // Extract structured emotional themes from journal AI analysis (metadata only)
            List<String> emotions = recentJournals.stream()
                    .filter(j -> j.getAiAnalysis() != null && j.getAiAnalysis().getEmotion() != null)
                    .map(j -> j.getAiAnalysis().getEmotion())
                    .distinct()
                    .collect(Collectors.toList());
            context.put("journalEmotions", emotions);

            // Extract journal tags from entry types
            Map<String, Long> typeDistribution = recentJournals.stream()
                    .collect(Collectors.groupingBy(JournalEntry::getType, Collectors.counting()));
            context.put("journalTypeDistribution", typeDistribution);

        } catch (Exception e) {
            log.debug("Could not build journal context: {}", e.getMessage());
            context.put("journalAvailable", false);
        }
    }

    private void buildWellnessContext(String userId, Map<String, Object> context) {
        try {
            var profile = wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(userId);
            if (profile.isEmpty()) {
                context.put("wellnessAvailable", false);
                return;
            }

            WellnessProfile wp = profile.get();
            context.put("wellnessAvailable", true);

            if (wp.getPrimaryFocus() != null) context.put("primaryFocus", wp.getPrimaryFocus());
            if (wp.getStressLevel() != null) context.put("stressLevel", wp.getStressLevel());
            if (wp.getSleepQuality() != null) context.put("sleepQuality", wp.getSleepQuality());
            if (wp.getLifestyleScore() != null) context.put("lifestyleScore", wp.getLifestyleScore());

        } catch (Exception e) {
            log.debug("Could not build wellness context: {}", e.getMessage());
            context.put("wellnessAvailable", false);
        }
    }

    private void buildInteractionContext(String userId, Map<String, Object> context) {
        try {
            Instant oneWeekAgo = Instant.now().minus(7, ChronoUnit.DAYS);
            List<RecommendationInteraction> recentInteractions =
                    interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                            userId, oneWeekAgo);

            // Content IDs recently shown/completed/dismissed
            Map<String, List<String>> byType = recentInteractions.stream()
                    .collect(Collectors.groupingBy(
                            RecommendationInteraction::getInteractionType,
                            Collectors.mapping(
                                    RecommendationInteraction::getContentId,
                                    Collectors.toList())));

            context.put("recentlyShown", byType.getOrDefault("SHOWN", List.of()));
            context.put("recentlyCompleted", byType.getOrDefault("COMPLETED", List.of()));
            context.put("recentlyDismissed", byType.getOrDefault("DISMISSED", List.of()));
            context.put("recentlyOpened", byType.getOrDefault("OPENED", List.of()));
            context.put("recentlyHelpful", byType.getOrDefault("HELPFUL", List.of()));
            context.put("recentlyNotUseful", byType.getOrDefault("NOT_USEFUL", List.of()));
            context.put("totalRecentInteractions", recentInteractions.size());

        } catch (Exception e) {
            log.debug("Could not build interaction context: {}", e.getMessage());
            context.put("totalRecentInteractions", 0);
        }
    }

    /**
     * Enrich the recommendation context with cross-feature signals
     * from the unified personalized context.
     */
    private void enrichWithPersonalizedContext(String userId, Map<String, Object> context) {
        try {
            PersonalizedContext pCtx = personalizationService.getContext(userId);
            if (pCtx == null) return;

            // Add emotional themes for better mood-based filtering
            if (pCtx.getEmotionalThemes() != null && !pCtx.getEmotionalThemes().isEmpty()) {
                context.put("emotionalThemes", pCtx.getEmotionalThemes());
            }

            // Add mood trend for trend-aware recommendations
            if (pCtx.getMoodTrend() != null) {
                context.put("moodTrend", pCtx.getMoodTrend());
            }

            // Add coach topics for topic-aware recommendations
            if (pCtx.getCoachTopics() != null && !pCtx.getCoachTopics().isEmpty()) {
                context.put("coachTopics", pCtx.getCoachTopics());
            }

            // Add journal activity level for engagement-aware recommendations
            if (pCtx.getJournalActivityLevel() != null) {
                context.put("journalActivityLevel", pCtx.getJournalActivityLevel());
            }

        } catch (Exception e) {
            // Personalization enrichment is best-effort
            log.debug("Could not enrich recommendation context with personalized context: {}",
                    e.getMessage());
        }
    }
}
