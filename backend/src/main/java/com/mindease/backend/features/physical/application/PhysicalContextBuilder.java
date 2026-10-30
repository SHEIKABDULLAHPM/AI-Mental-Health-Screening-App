package com.mindease.backend.features.physical.application;

import java.time.LocalDate;
import java.util.List;

import org.springframework.stereotype.Service;

import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.ExerciseSession;
import com.mindease.backend.features.physical.domain.ExerciseSessionRepository;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.security.UserTimeZoneHolder;
import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;

/**
 * Builds the structured physical-wellness context the future Mind–Body
 * Pattern Engine will consume.
 *
 * <p>Phase 1 deliberately does NOT wire this into the AI coach or prompts:
 * it only prepares a bounded, aggregated (never raw) representation so the AI
 * layer can adopt it later without touching the physical domain. Only
 * supportive wellness framing belongs here — never medical interpretation.</p>
 */
@Service
public class PhysicalContextBuilder {

    private static final int WINDOW_DAYS = 7;

    private final DailyActivityRepository dailyActivity;
    private final SleepSessionRepository sleepSessions;
    private final ExerciseSessionRepository exerciseSessions;
    private final PhysicalAggregationService aggregation;

    public PhysicalContextBuilder(DailyActivityRepository dailyActivity,
                                  SleepSessionRepository sleepSessions,
                                  ExerciseSessionRepository exerciseSessions,
                                  PhysicalAggregationService aggregation) {
        this.dailyActivity = dailyActivity;
        this.sleepSessions = sleepSessions;
        this.exerciseSessions = exerciseSessions;
        this.aggregation = aggregation;
    }

    /**
     * Bounded weekly snapshot of physical signals. Fields are null when the
     * corresponding data was never received.
     */
    public PhysicalWeekContext buildWeek(String userId) {
        var zone = ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
        LocalDate today = LocalDate.now(zone);

        List<DailyActivity> days = dailyActivity
                .findByUserIdAndDateBetweenOrderByDateDesc(userId,
                        today.minusDays(WINDOW_DAYS - 1), today);
        PhysicalAggregationService.WeeklyActivitySummary activity =
                aggregation.weeklyActivity(days, today);

        List<SleepSession> sleep = sleepSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                userId, today.minusDays(WINDOW_DAYS).atStartOfDay(zone).toInstant(),
                java.time.Instant.now());
        PhysicalAggregationService.WeeklySleepSummary sleepSummary =
                aggregation.weeklySleep(sleep, today, today.minusDays(WINDOW_DAYS - 1));

        List<ExerciseSession> exercise = exerciseSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                        userId, today.minusDays(WINDOW_DAYS).atStartOfDay(zone).toInstant(),
                        java.time.Instant.now());
        long exerciseMillis = 0;
        int exerciseCount = 0;
        for (ExerciseSession session : exercise) {
            if (session.getDurationMillis() != null) {
                exerciseMillis += session.getDurationMillis();
                exerciseCount++;
            }
        }

        return new PhysicalWeekContext(
                activity.daysWithData(),
                activity.totalSteps(),
                activity.averageSteps(),
                activity.totalDistanceMeters(),
                activity.totalCaloriesKcal(),
                sleepSummary.sessionsWithData(),
                sleepSummary.averageDurationMillis(),
                exerciseCount == 0 ? null : exerciseMillis,
                exerciseCount);
    }

    /**
     * Aggregated weekly physical signals for AI context. Never contains raw
     * readings or device identifiers.
     */
    public record PhysicalWeekContext(
            int activeDays,
            Integer totalSteps,
            Double averageSteps,
            Double totalDistanceMeters,
            Double totalCaloriesKcal,
            int sleepSessions,
            Long averageSleepMillis,
            Long totalExerciseMillis,
            int exerciseSessions) {
    }
}
