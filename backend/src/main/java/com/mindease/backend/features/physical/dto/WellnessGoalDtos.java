package com.mindease.backend.features.physical.dto;

import java.util.List;
import java.util.Map;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * User-configurable wellness goals plus read-only progress computed from
 * actual records. A {@code null} target means the user has not chosen one.
 */
public final class WellnessGoalDtos {

    private WellnessGoalDtos() {
    }

    public record GoalRequest(
            @Min(value = 500, message = "dailySteps must be at least 500")
            @Max(value = 100000, message = "dailySteps must be at most 100000")
            Integer dailySteps,
            @Min(value = 1, message = "dailyActiveMinutes must be at least 1")
            @Max(value = 600, message = "dailyActiveMinutes must be at most 600")
            Integer dailyActiveMinutes,
            @Min(value = 1, message = "weeklyWorkoutMinutes must be at least 1")
            @Max(value = 2000, message = "weeklyWorkoutMinutes must be at most 2000")
            Integer weeklyWorkoutMinutes,
            @Min(value = 60, message = "dailySleepMinutes must be at least 60")
            @Max(value = 960, message = "dailySleepMinutes must be at most 960")
            Integer dailySleepMinutes,
            @Min(value = 250, message = "dailyHydrationMl must be at least 250")
            @Max(value = 10000, message = "dailyHydrationMl must be at most 10000")
            Integer dailyHydrationMl) {
    }

    public record GoalTargets(
            Integer dailySteps,
            Integer dailyActiveMinutes,
            Integer weeklyWorkoutMinutes,
            Integer dailySleepMinutes,
            Integer dailyHydrationMl) {
    }

    /**
     * Progress for one goal. {@code dataAvailable=false} means the underlying
     * source recorded nothing for the period — progress is then unknown rather
     * than 0 %.
     */
    public record GoalProgress(
            String metric,
            String label,
            String unit,
            String period,
            Integer target,
            Double current,
            Double remaining,
            Double progress,
            Boolean met,
            boolean dataAvailable,
            String source,
            String note,
            /** USER, AI_RECOMMENDED, or null when no target is set. */
            String targetSource) {
    }

    /** One AI-suggested target, already range-checked before it is applied. */
    public record AiRecommendation(
            String metric,
            Integer value,
            String rationale) {
    }

    public record ApplyRecommendationsRequest(List<AiRecommendation> recommendations) {
    }

    /**
     * Outcome of applying AI suggestions. {@code skipped} explains every
     * suggestion that was not written, so a client never claims an update that
     * did not happen.
     */
    public record ApplyRecommendationsResponse(
            GoalsResponse goals,
            List<String> applied,
            List<String> skipped) {
    }

    public record StreakResult(
            String metric,
            int currentStreak,
            int longestStreak,
            int daysEvaluated,
            int daysWithData,
            String note) {
    }

    public record GoalsResponse(
            GoalTargets goals,
            boolean customized,
            List<GoalProgress> progress,
            Map<String, StreakResult> streaks,
            GoalTargets suggestedDefaults,
            List<String> guidance) {
    }
}
