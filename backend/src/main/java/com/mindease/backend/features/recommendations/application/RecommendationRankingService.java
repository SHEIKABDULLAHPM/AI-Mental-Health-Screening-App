package com.mindease.backend.features.recommendations.application;

import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.mindease.backend.features.recommendations.domain.RecommendationContent;

/**
 * Deterministic, explainable ranking engine for recommendations.
 * Ranking is weighted and version-controlled.
 */
@Component
public class RecommendationRankingService {

    private static final Logger log = LoggerFactory.getLogger(RecommendationRankingService.class);

    /** Ranking algorithm version for reproducibility */
    public static final String RANKING_VERSION = "rec-rank-v2";

    // Configurable weights — context-aware scoring
    private static final double WEIGHT_CONTEXT_RELEVANCE = 3.0;
    private static final double WEIGHT_PREFERENCE_MATCH = 2.5;
    private static final double WEIGHT_STRESS_RELIEF = 2.0;
    private static final double WEIGHT_DIVERSITY_BONUS = 1.5;
    private static final double WEIGHT_POSITIVE_FEEDBACK = 1.0;
    private static final double WEIGHT_MOOD_TREND = 1.8;
    private static final double WEIGHT_EMOTIONAL_THEME = 1.2;
    private static final double WEIGHT_COACH_TOPIC = 1.0;
    private static final double WEIGHT_JOURNAL_ACTIVITY = 0.8;
    private static final double WEIGHT_TIME_OF_DAY = 0.6;

    // Penalties
    private static final double PENALTY_RECENT_EXPOSURE = -2.0;
    private static final double PENALTY_RECENT_COMPLETION = -3.0;
    private static final double PENALTY_NOT_USEFUL = -1.5;

    /**
     * Rank candidates based on dynamic, context-aware scoring.
     * Uses mood trends, journal themes, coach topics, time-of-day,
     * and interaction history to generate personalized rankings.
     */
    @SuppressWarnings("unchecked")
    public List<ScoredRecommendation> rank(
            List<RecommendationContent> candidates,
            Map<String, Object> context) {

        String dominantMood = (String) context.getOrDefault("dominantMood", "neutral");
        String primaryFocus = (String) context.get("primaryFocus");
        String stressLevel = (String) context.get("stressLevel");
        String sleepQuality = (String) context.get("sleepQuality");
        String moodTrend = (String) context.getOrDefault("moodTrend", "unknown");
        List<String> emotionalThemes = (List<String>) context.getOrDefault("emotionalThemes", List.of());
        List<String> journalEmotions = (List<String>) context.getOrDefault("journalEmotions", List.of());
        List<String> coachTopics = (List<String>) context.getOrDefault("coachTopics", List.of());
        String journalActivityLevel = (String) context.get("journalActivityLevel");
        Set<String> recentlyCompleted = Set.copyOf(
                (List<String>) context.getOrDefault("recentlyCompleted", List.of()));
        Set<String> recentlyShown = Set.copyOf(
                (List<String>) context.getOrDefault("recentlyShown", List.of()));
        Set<String> recentlyDismissed = Set.copyOf(
                (List<String>) context.getOrDefault("recentlyDismissed", List.of()));
        Set<String> recentlyNotUseful = Set.copyOf(
                (List<String>) context.getOrDefault("recentlyNotUseful", List.of()));
        Set<String> recentlyHelpful = Set.copyOf(
                (List<String>) context.getOrDefault("recentlyHelpful", List.of()));

        // Build combined theme set from all sources
        Set<String> allThemes = new java.util.LinkedHashSet<>();
        allThemes.addAll(emotionalThemes);
        allThemes.addAll(journalEmotions);
        allThemes.addAll(coachTopics);

        Map<String, String> moodToCategory = Map.of(
                "happy", "meditation",
                "calm", "meditation",
                "stressed", "exercises",
                "anxious", "exercises",
                "sad", "articles",
                "low", "articles",
                "tired", "sounds",
                "neutral", "personalized"
        );

        String focusCategory = moodToCategory.getOrDefault(dominantMood, "personalized");

        return candidates.stream()
                .map(content -> {
                    double score = 0.0;
                    StringBuilder reason = new StringBuilder();

                    // 1. Context relevance (mood → category match)
                    if (content.getCategory().equals(focusCategory)) {
                        score += WEIGHT_CONTEXT_RELEVANCE;
                        reason.append("Based on your recent check-ins, ");
                        switch (dominantMood) {
                            case "stressed", "anxious" -> reason.append("activities that help with stress relief may be helpful right now. ");
                            case "sad", "low" -> reason.append("reflective activities could support you right now. ");
                            case "tired" -> reason.append("calming activities might help you rest. ");
                            case "happy", "calm" -> reason.append("you're in a great headspace for mindful activities. ");
                            default -> reason.append("this aligns with how you've been feeling. ");
                        }
                    }

                    // 2. Mood trend awareness
                    if (!"unknown".equals(moodTrend)) {
                        boolean trendRelevant = switch (moodTrend) {
                            case "declining" -> "exercises".equals(content.getCategory()) ||
                                    "meditation".equals(content.getCategory());
                            case "improving" -> "articles".equals(content.getCategory()) ||
                                    "personalized".equals(content.getCategory());
                            case "fluctuating" -> "sounds".equals(content.getCategory()) ||
                                    "meditation".equals(content.getCategory());
                            default -> false;
                        };
                        if (trendRelevant) {
                            score += WEIGHT_MOOD_TREND;
                            reason.append("Because your mood has been " + moodTrend + " lately. ");
                        }
                    }

                    // 3. Emotional theme matching (cross-feature signals)
                    if (content.getTags() != null && !allThemes.isEmpty()) {
                        long themeOverlap = content.getTags().stream()
                                .filter(tag -> allThemes.stream()
                                        .anyMatch(theme -> theme.toLowerCase().contains(tag.toLowerCase())
                                                || tag.toLowerCase().contains(theme.toLowerCase())))
                                .count();
                        if (themeOverlap > 0) {
                            score += WEIGHT_EMOTIONAL_THEME * themeOverlap;
                            reason.append("Related to themes from your journal and mood patterns. ");
                        }
                    }

                    // 4. Coach topic relevance
                    if (coachTopics != null && !coachTopics.isEmpty() && content.getTags() != null) {
                        boolean coachMatch = coachTopics.stream()
                                .anyMatch(topic -> content.getTags().stream()
                                        .anyMatch(tag -> tag.toLowerCase().contains(topic.toLowerCase())
                                                || topic.toLowerCase().contains(tag.toLowerCase())));
                        if (coachMatch) {
                            score += WEIGHT_COACH_TOPIC;
                            reason.append("Connects to topics you've explored with the AI Coach. ");
                        }
                    }

                    // 5. Journal activity awareness
                    if ("active".equals(journalActivityLevel) || "very_active".equals(journalActivityLevel)) {
                        if ("articles".equals(content.getCategory())) {
                            score += WEIGHT_JOURNAL_ACTIVITY;
                            reason.append("Since you've been writing regularly, a reflection prompt may resonate. ");
                        }
                    }

                    // 6. Primary focus match from wellness profile
                    if (primaryFocus != null && content.getTags() != null) {
                        String focusLower = primaryFocus.toLowerCase();
                        boolean focusMatch = content.getTags().stream()
                                .anyMatch(tag -> focusLower.contains(tag.toLowerCase()));
                        if (focusMatch) {
                            score += WEIGHT_PREFERENCE_MATCH;
                            reason.append("Aligns with your wellness goal of " + primaryFocus + ". ");
                        }
                    }

                    // 7. Stress-based relevance
                    if ("high".equalsIgnoreCase(stressLevel) || "moderate".equalsIgnoreCase(stressLevel)) {
                        if ("exercises".equals(content.getCategory()) ||
                            "meditation".equals(content.getCategory()) ||
                            "sounds".equals(content.getCategory())) {
                            score += WEIGHT_STRESS_RELIEF;
                            reason.append("Helpful for managing stress. ");
                        }
                    }

                    // 8. Sleep quality relevance
                    if ("poor".equalsIgnoreCase(sleepQuality)) {
                        if ("sounds".equals(content.getCategory()) ||
                            "exercises".equals(content.getCategory())) {
                            score += 1.5;
                            reason.append("May help improve your sleep. ");
                        }
                    }

                    // 9. Time-of-day relevance
                    int hour = java.time.LocalTime.now().getHour();
                    boolean timeRelevant = switch (content.getCategory()) {
                        case "sounds" -> hour >= 20 || hour <= 6; // evening/night
                        case "exercises" -> hour >= 6 && hour <= 10; // morning
                        case "meditation" -> hour >= 20 || (hour >= 6 && hour <= 8); // morning/evening
                        case "articles" -> hour >= 12 && hour <= 18; // afternoon
                        default -> false;
                    };
                    if (timeRelevant) {
                        score += WEIGHT_TIME_OF_DAY;
                        reason.append("Great for this time of day. ");
                    }

                    // 10. Helpful feedback bonus (stronger signal)
                    if (recentlyHelpful.contains(content.getId())) {
                        score += WEIGHT_POSITIVE_FEEDBACK * 2;
                        reason.append("You rated this as helpful before. ");
                    }

                    // 11. Diversity: bonus for categories not recently shown
                    if (!recentlyShown.contains(content.getId())) {
                        score += WEIGHT_DIVERSITY_BONUS;
                    }

                    // 12. Penalties
                    if (recentlyCompleted.contains(content.getId())) {
                        score += PENALTY_RECENT_COMPLETION;
                    }
                    if (recentlyShown.contains(content.getId())) {
                        score += PENALTY_RECENT_EXPOSURE;
                    }
                    if (recentlyDismissed.contains(content.getId())) {
                        score += PENALTY_RECENT_EXPOSURE;
                    }
                    if (recentlyNotUseful.contains(content.getId())) {
                        score += PENALTY_NOT_USEFUL;
                    }

                    // 13. Tag-based relevance bonus
                    if (content.getTags() != null && content.getTags().contains(dominantMood)) {
                        score += 1.0;
                        reason.append("Tailored for how you're feeling. ");
                    }

                    // If no specific reason found, use a context-aware neutral explanation
                    if (reason.length() == 0) {
                        if (dominantMood != null && !"neutral".equals(dominantMood)) {
                            reason.append("Based on your current mood, this may be a good fit. ");
                        } else {
                            reason.append("A wellness activity to support your day. ");
                        }
                    }

                    return new ScoredRecommendation(content, score, reason.toString().trim());
                })
                .sorted(Comparator.comparingDouble(ScoredRecommendation::score).reversed())
                .collect(Collectors.toList());
    }

    /**
     * A recommendation with its computed score and reason.
     */
    public record ScoredRecommendation(
            RecommendationContent content,
            double score,
            String reason
    ) {
    }
}
