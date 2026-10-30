package com.mindease.backend.progress.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import com.mindease.backend.coach.domain.Conversation;
import com.mindease.backend.coach.domain.ConversationRepository;
import com.mindease.backend.features.habits.domain.Habit;
import com.mindease.backend.features.habits.domain.HabitRepository;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.mood.application.MoodTrendAnalyzer;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationContentRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteraction;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.progress.dto.ProgressDto;
import com.mindease.backend.progress.dto.ProgressDto.ActivityProgress;
import com.mindease.backend.progress.dto.ProgressDto.EngagementProgress;
import com.mindease.backend.progress.dto.ProgressDto.JournalProgress;
import com.mindease.backend.progress.dto.ProgressDto.MoodProgress;
import com.mindease.backend.progress.dto.ProgressDto.ProgressInsight;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

/**
 * Aggregates real progress data from all features into a single DTO.
 * Every field is computed from actual MongoDB data — no static or fabricated values.
 * Distinguishes between actual data, insufficient data, and estimated trends.
 */
@Service
public class ProgressService {

    private static final Logger log = LoggerFactory.getLogger(ProgressService.class);

    private final MoodEntryRepository moodRepo;
    private final JournalEntryRepository journalRepo;
    private final RecommendationInteractionRepository interactionRepo;
    private final ConversationRepository conversationRepo;
    private final WellnessProfileRepository wellnessRepo;
    private final PersonalizationService personalizationService;

    private final com.mindease.backend.features.habits.domain.HabitRepository habitRepo;
    private final MoodTrendAnalyzer moodTrendAnalyzer;
    @SuppressWarnings("unused") // Used in engagement calculation

    public ProgressService(
            MoodEntryRepository moodRepo,
            JournalEntryRepository journalRepo,
            RecommendationInteractionRepository interactionRepo,
            ConversationRepository conversationRepo,
            WellnessProfileRepository wellnessRepo,
            PersonalizationService personalizationService,
            HabitRepository habitRepo,
            MoodTrendAnalyzer moodTrendAnalyzer) {
        this.moodRepo = moodRepo;
        this.journalRepo = journalRepo;
        this.interactionRepo = interactionRepo;
        this.conversationRepo = conversationRepo;
        this.wellnessRepo = wellnessRepo;
        this.personalizationService = personalizationService;
        this.habitRepo = habitRepo;
        this.moodTrendAnalyzer = moodTrendAnalyzer;
    }

    /**
     * Build the complete progress DTO for the authenticated user.
     * Each section is failure-isolated — one section's error doesn't break others.
     */
    public ProgressDto getProgress(String userId) {
        Instant now = Instant.now();
        Instant weekAgo = now.minus(7, ChronoUnit.DAYS);

        // Build each section independently
        MoodProgress mood = buildMoodProgress(userId, now, weekAgo);
        JournalProgress journal = buildJournalProgress(userId, weekAgo);
        ActivityProgress activities = buildActivityProgress(userId, weekAgo);
        EngagementProgress engagement = buildEngagementProgress(userId, weekAgo);
        Integer wellnessScore = getWellnessScore(userId);
        String wellnessTrend = deriveWellnessTrend(mood, journal, activities);
        List<ProgressInsight> insights = generateInsights(mood, journal, activities, engagement);
        String dataAvailability = assessDataAvailability(mood, journal, activities);

        return new ProgressDto(
                wellnessScore,
                getWellnessScoreLabel(wellnessScore),
                wellnessTrend,
                mood,
                journal,
                activities,
                engagement,
                insights,
                dataAvailability,
                now
        );
    }

    // ── Mood progress ──

    private MoodProgress buildMoodProgress(String userId, Instant now, Instant weekAgo) {
        try {
            List<MoodEntry> allRecent = moodRepo.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                    userId, now.minus(365, ChronoUnit.DAYS));
            List<MoodEntry> thisWeek = allRecent.stream()
                    .filter(e -> e.getRecordedAt() != null && e.getRecordedAt().isAfter(weekAgo))
                    .toList();

            if (allRecent.isEmpty()) {
                return new MoodProgress(0, 0, 0, 0, null, "unknown", "No mood data yet",
                        Map.of(), false);
            }

            // Distribution
            Map<String, Long> distribution = allRecent.stream()
                    .filter(e -> e.getMood() != null)
                    .collect(Collectors.groupingBy(MoodEntry::getMood, Collectors.counting()));

            String dominant = distribution.entrySet().stream()
                    .max(Map.Entry.comparingByValue())
                    .map(Map.Entry::getKey)
                    .orElse("neutral");

            // Streak calculation
            ZoneId utc = ZoneId.of("UTC");
            LocalDate today = LocalDate.now(utc);
            List<LocalDate> entryDates = allRecent.stream()
                    .filter(e -> e.getRecordedAt() != null)
                    .map(e -> e.getRecordedAt().atZone(utc).toLocalDate())
                    .distinct()
                    .sorted((a, b) -> b.compareTo(a))
                    .toList();

            int currentStreak = 0;
            LocalDate checkDate = today;
            for (LocalDate date : entryDates) {
                if (date.equals(checkDate)) {
                    currentStreak++;
                    checkDate = checkDate.minusDays(1);
                } else if (date.isBefore(checkDate)) {
                    break;
                }
            }

            int longestStreak = 0;
            int streak = 0;
            LocalDate prevDate = null;
            for (LocalDate date : entryDates.reversed()) {
                if (prevDate != null && date.equals(prevDate.plusDays(1))) {
                    streak++;
                } else {
                    streak = 1;
                }
                longestStreak = Math.max(longestStreak, streak);
                prevDate = date;
            }

            // Trend
            String trend = computeMoodTrend(allRecent);
            String trendDesc = switch (trend) {
                case "improving" -> "Your mood has been trending positively.";
                case "declining" -> "Your mood has been trending downward — consider self-care.";
                case "stable" -> "Your mood has been fairly consistent.";
                case "fluctuating" -> "Your mood has been varying — this is normal.";
                default -> "Not enough data to determine a trend.";
            };

            return new MoodProgress(
                    allRecent.size(),
                    thisWeek.size(),
                    currentStreak,
                    longestStreak,
                    dominant,
                    trend,
                    trendDesc,
                    distribution,
                    true
            );
        } catch (Exception e) {
            log.debug("Could not build mood progress: {}", e.getMessage());
            return new MoodProgress(0, 0, 0, 0, null, "unknown", "Unavailable",
                    Map.of(), false);
        }
    }

    // ── Journal progress ──

    private JournalProgress buildJournalProgress(String userId, Instant weekAgo) {
        try {
            long total = journalRepo.countByUserId(userId);
            List<JournalEntry> recent = journalRepo.findByUserIdOrderByCreatedAtDesc(
                    userId, PageRequest.of(0, 30));
            long thisWeek = recent.stream()
                    .filter(j -> j.getCreatedAt() != null && j.getCreatedAt().isAfter(weekAgo))
                    .count();

            if (total == 0) {
                return new JournalProgress(0, 0, "inactive", List.of(), false);
            }

            // Activity level
            String level;
            if (thisWeek >= 5) level = "very_active";
            else if (thisWeek >= 3) level = "active";
            else if (thisWeek >= 1) level = "moderate";
            else level = "occasional";

            // Recent emotions from AI analysis
            List<String> emotions = recent.stream()
                    .filter(j -> j.getAiAnalysis() != null && j.getAiAnalysis().getEmotion() != null)
                    .map(j -> j.getAiAnalysis().getEmotion())
                    .distinct()
                    .limit(5)
                    .toList();

            return new JournalProgress(
                    (int) total,
                    (int) thisWeek,
                    level,
                    emotions,
                    true
            );
        } catch (Exception e) {
            log.debug("Could not build journal progress: {}", e.getMessage());
            return new JournalProgress(0, 0, "inactive", List.of(), false);
        }
    }

    // ── Activity progress ──

    private ActivityProgress buildActivityProgress(String userId, Instant weekAgo) {
        try {
            List<RecommendationInteraction> allRecent =
                    interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                            userId, Instant.now().minus(90, ChronoUnit.DAYS));
            List<RecommendationInteraction> thisWeek =
                    allRecent.stream()
                            .filter(i -> i.getCreatedAt() != null && i.getCreatedAt().isAfter(weekAgo))
                            .toList();

            int completed = (int) allRecent.stream()
                    .filter(i -> "COMPLETED".equals(i.getInteractionType()))
                    .count();
            int completedThisWeek = (int) thisWeek.stream()
                    .filter(i -> "COMPLETED".equals(i.getInteractionType()))
                    .count();
            int helpful = (int) allRecent.stream()
                    .filter(i -> "HELPFUL".equals(i.getInteractionType()))
                    .count();
            int dismissed = (int) allRecent.stream()
                    .filter(i -> "DISMISSED".equals(i.getInteractionType()))
                    .count();

            return new ActivityProgress(
                    completedThisWeek,
                    completed,
                    helpful,
                    dismissed,
                    List.of(), // Titles would require joining with content — simplified for now
                    !allRecent.isEmpty()
            );
        } catch (Exception e) {
            log.debug("Could not build activity progress: {}", e.getMessage());
            return new ActivityProgress(0, 0, 0, 0, List.of(), false);
        }
    }

    // ── Engagement progress ──

    private EngagementProgress buildEngagementProgress(String userId, Instant weekAgo) {
        try {
            int featuresUsed = 0;
            int activeFeatures = 0;

            // Check mood
            long moodCount = moodRepo.countByUserId(userId);
            if (moodCount > 0) featuresUsed++;
            boolean moodActive = moodRepo.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                    userId, weekAgo, PageRequest.of(0, 1)).size() > 0;
            if (moodActive) activeFeatures++;

            // Check journal
            long journalCount = journalRepo.countByUserId(userId);
            if (journalCount > 0) featuresUsed++;

            // Check recommendations
            long interactionCount = interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                    userId, weekAgo).size();
            if (interactionCount > 0) {
                featuresUsed++;
                activeFeatures++;
            }

            // Check coach
            List<Conversation> conversations = conversationRepo.findByUserIdOrderByUpdatedAtDesc(
                    userId, PageRequest.of(0, 50));
            int coachConvos = conversations.size();
            if (coachConvos > 0) featuresUsed++;
            boolean coachActive = conversations.stream()
                    .anyMatch(c -> c.getUpdatedAt() != null && c.getUpdatedAt().isAfter(weekAgo));
            if (coachActive) activeFeatures++;

            // Consistency level
            String consistency;
            if (activeFeatures >= 3) consistency = "high";
            else if (activeFeatures >= 2) consistency = "moderate";
            else if (activeFeatures >= 1) consistency = "low";
            else consistency = "inactive";

            String summary = switch (consistency) {
                case "high" -> "You're actively engaging across multiple features — great job!";
                case "moderate" -> "You're making good progress. Try exploring more features.";
                case "low" -> "Small steps count. Try checking in with your mood today.";
                default -> "Start tracking your mood to see your engagement patterns.";
            };

            return new EngagementProgress(
                    featuresUsed,
                    activeFeatures,
                    coachConvos,
                    consistency,
                    summary
            );
        } catch (Exception e) {
            log.debug("Could not build engagement progress: {}", e.getMessage());
            return new EngagementProgress(0, 0, 0, "inactive", "Progress data unavailable.");
        }
    }

    // ── Wellness score ──

    private Integer getWellnessScore(String userId) {
        try {
            var profile = wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(userId);
            return profile.map(WellnessProfile::getWellnessScore).orElse(null);
        } catch (Exception e) {
            return null;
        }
    }

    private String deriveWellnessTrend(MoodProgress mood, JournalProgress journal,
            ActivityProgress activities) {
        // Compute wellness trend from real data signals
        int positiveSignals = 0;
        int negativeSignals = 0;

        if ("improving".equals(mood.moodTrend())) positiveSignals++;
        if ("declining".equals(mood.moodTrend())) negativeSignals++;
        if (mood.currentStreak() >= 3) positiveSignals++;
        if ("active".equals(journal.activityLevel()) || "very_active".equals(journal.activityLevel())) positiveSignals++;
        if (activities.completedThisWeek() > 0) positiveSignals++;
        if (activities.helpfulCount() > activities.dismissedCount()) positiveSignals++;

        if (positiveSignals > negativeSignals + 1) return "improving";
        if (negativeSignals > positiveSignals + 1) return "needs_attention";
        return "stable";
    }

    private String getWellnessScoreLabel(Integer score) {
        if (score == null) return "Complete a screening to see your score.";
        if (score >= 80) return "Excellent — keep up the great work!";
        if (score >= 60) return "Good — you're on a positive path.";
        if (score >= 40) return "Fair — there's room for improvement.";
        return "Needs attention — consider exploring the recommended activities.";
    }

    // ── Trend computation ──
    // Single source of truth: MoodTrendAnalyzer. This wrapper only extracts
    // the direction string for the progress DTO — no forked math.

    private String computeMoodTrend(List<MoodEntry> entries) {
        try {
            Object direction = moodTrendAnalyzer.analyzeTrend(entries).get("direction");
            return direction instanceof String s ? s : "unknown";
        } catch (Exception e) {
            log.debug("Could not compute mood trend: {}", e.getMessage());
            return "unknown";
        }
    }

    // ── Insights generation ──

    private List<ProgressInsight> generateInsights(
            MoodProgress mood, JournalProgress journal,
            ActivityProgress activities, EngagementProgress engagement) {

        List<ProgressInsight> insights = new ArrayList<>();

        // Mood streak insight
        if (mood.hasData() && mood.currentStreak() >= 3) {
            insights.add(new ProgressInsight(
                    "streak",
                    "Mood streak: " + mood.currentStreak() + " days",
                    "You've logged your mood for " + mood.currentStreak() + " consecutive days. Consistency helps build self-awareness.",
                    "local_fire_department"
            ));
        }

        // Mood trend insight
        if (mood.hasData() && "improving".equals(mood.moodTrend())) {
            insights.add(new ProgressInsight(
                    "trend",
                    "Mood is improving",
                    "Your recent check-ins show a positive upward trend. Keep up the momentum!",
                    "trending_up"
            ));
        } else if (mood.hasData() && "declining".equals(mood.moodTrend())) {
            insights.add(new ProgressInsight(
                    "trend",
                    "Mood needs attention",
                    "Your mood has been trending downward. Consider trying a breathing exercise or journaling.",
                    "trending_down"
            ));
        }

        // Journal insight
        if (journal.hasData() && "active".equals(journal.activityLevel())) {
            insights.add(new ProgressInsight(
                    "journal",
                    "Consistent journaling",
                    "You've been writing regularly. Journaling helps process emotions and build self-understanding.",
                    "edit_note"
            ));
        } else if (journal.hasData() && "inactive".equals(journal.activityLevel())) {
            insights.add(new ProgressInsight(
                    "journal",
                    "Try journaling",
                    "Writing down your thoughts can help clarify feelings. Even a few sentences count.",
                    "edit_note"
            ));
        }

        // Activity insight
        if (activities.completedThisWeek() > 0) {
            insights.add(new ProgressInsight(
                    "activity",
                    "Active this week",
                    "You've completed " + activities.completedThisWeek() + " wellness activities. Every step counts.",
                    "check_circle"
            ));
        }

        // Engagement insight
        if ("high".equals(engagement.consistencyLevel())) {
            insights.add(new ProgressInsight(
                    "engagement",
                    "Great engagement",
                    "You're actively using multiple features. This holistic approach supports overall wellbeing.",
                    "emoji_events"
            ));
        }

        return insights.stream().limit(5).toList();
    }

    // ── Data availability ──

    private String assessDataAvailability(MoodProgress mood, JournalProgress journal,
            ActivityProgress activities) {
        int dataPoints = 0;
        if (mood.hasData()) dataPoints++;
        if (journal.hasData()) dataPoints++;
        if (activities.hasData()) dataPoints++;

        if (dataPoints >= 3) return "sufficient";
        if (dataPoints >= 2) return "partial";
        if (dataPoints >= 1) return "limited";
        return "insufficient";
    }


}
