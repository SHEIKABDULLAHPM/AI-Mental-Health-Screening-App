package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.springframework.stereotype.Service;

import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.ExerciseSession;
import com.mindease.backend.features.physical.domain.ExerciseSessionRepository;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.WellnessGoal;
import com.mindease.backend.features.physical.domain.WellnessGoalRepository;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Goal configuration plus progress and streaks computed from real records.
 *
 * <p>Rules that keep this honest:</p>
 * <ul>
 *   <li>A goal only exists once the user sets it ({@code null} target = unset).</li>
 *   <li>Progress requires a source record; missing data reports
 *       {@code dataAvailable=false} instead of 0 %.</li>
 *   <li>Streaks break on a day without data, and exclude the in-progress
 *       current day, so a partial day never flatters or punishes the user.</li>
 * </ul>
 */
@Service
public class WellnessGoalService {

    static final int STREAK_WINDOW_DAYS = 30;

    private final WellnessGoalRepository goals;
    private final DailyActivityRepository dailyActivity;
    private final SleepSessionRepository sleepSessions;
    private final ExerciseSessionRepository exerciseSessions;
    private final HydrationService hydration;

    public WellnessGoalService(WellnessGoalRepository goals,
                               DailyActivityRepository dailyActivity,
                               SleepSessionRepository sleepSessions,
                               ExerciseSessionRepository exerciseSessions,
                               HydrationService hydration) {
        this.goals = goals;
        this.dailyActivity = dailyActivity;
        this.sleepSessions = sleepSessions;
        this.exerciseSessions = exerciseSessions;
        this.hydration = hydration;
    }

    public WellnessGoalDtos.GoalsResponse overview(String userId) {
        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        WellnessGoal goal = goals.findByUserId(userId).orElse(null);

        List<WellnessGoalDtos.GoalProgress> progress = new ArrayList<>();
        Map<String, WellnessGoalDtos.StreakResult> streaks = new LinkedHashMap<>();

        Integer stepTarget = goal == null ? null : goal.getDailySteps();
        progress.add(dailyActivityProgress(userId, today, stepTarget,
                targetSource(goal, "dailySteps")));
        streaks.put("steps", streak(userId, today, "steps", stepTarget));

        Integer activeTarget = goal == null ? null : goal.getDailyActiveMinutes();
        progress.add(activeMinutesProgress(userId, today, activeTarget,
                targetSource(goal, "dailyActiveMinutes")));
        streaks.put("activeMinutes", streak(userId, today, "activeMinutes", activeTarget));

        Integer sleepTarget = goal == null ? null : goal.getDailySleepMinutes();
        progress.add(sleepProgress(userId, today, sleepTarget,
                targetSource(goal, "dailySleepMinutes")));
        streaks.put("sleep", streak(userId, today, "sleep", sleepTarget));

        Integer hydrationTarget = goal == null ? null : goal.getDailyHydrationMl();
        progress.add(hydrationProgress(userId, today, hydrationTarget,
                targetSource(goal, "dailyHydrationMl")));
        streaks.put("hydration", streak(userId, today, "hydration", hydrationTarget));

        Integer workoutTarget = goal == null ? null : goal.getWeeklyWorkoutMinutes();
        progress.add(workoutProgress(userId, today, workoutTarget,
                targetSource(goal, "weeklyWorkoutMinutes")));

        return new WellnessGoalDtos.GoalsResponse(
                new WellnessGoalDtos.GoalTargets(
                        stepTarget,
                        activeTarget,
                        workoutTarget,
                        sleepTarget,
                        hydrationTarget),
                goal != null,
                progress,
                streaks,
                new WellnessGoalDtos.GoalTargets(7_000, 30, 120, 480, 2_000),
                List.of(
                        "Targets are yours to set and change. They are not a prescription.",
                        "AI-suggested targets are labelled and never overwrite goals you set yourself.",
                        "Activity goals should feel sustainable; stop if you feel unwell.",
                        "Sleep targets should not encourage sleep restriction.",
                        "Hydration needs vary by person and conditions — adjust with a clinician "
                                + "if you have one that affects fluid balance."));
    }

    /** Replaces the user's goal set. A {@code null} field clears that goal. */
    public WellnessGoalDtos.GoalsResponse update(String userId, WellnessGoalDtos.GoalRequest request) {
        WellnessGoal goal = goals.findByUserId(userId).orElseGet(() -> {
            WellnessGoal created = new WellnessGoal();
            created.setUserId(userId);
            created.setCreatedAt(Instant.now());
            return created;
        });
        goal.setDailySteps(request.dailySteps());
        goal.setDailyActiveMinutes(request.dailyActiveMinutes());
        goal.setWeeklyWorkoutMinutes(request.weeklyWorkoutMinutes());
        goal.setDailySleepMinutes(request.dailySleepMinutes());
        goal.setDailyHydrationMl(request.dailyHydrationMl());
        goal.setUpdatedAt(Instant.now());
        // An explicit save is the user's own choice: every target it touches is
        // marked USER and a cleared target loses its old provenance.
        Map<String, String> sources = new LinkedHashMap<>();
        putSource(sources, "dailySteps", request.dailySteps());
        putSource(sources, "dailyActiveMinutes", request.dailyActiveMinutes());
        putSource(sources, "weeklyWorkoutMinutes", request.weeklyWorkoutMinutes());
        putSource(sources, "dailySleepMinutes", request.dailySleepMinutes());
        putSource(sources, "dailyHydrationMl", request.dailyHydrationMl());
        goal.setTargetSources(sources);
        goals.save(goal);
        return overview(userId);
    }

    /**
     * Applies AI-suggested targets without ever overwriting a target the user
     * set themselves. Invalid values and user-owned metrics are reported in
     * {@code skipped}; only written metrics appear in {@code applied}.
     */
    public WellnessGoalDtos.ApplyRecommendationsResponse applyAiRecommendations(
            String userId, List<WellnessGoalDtos.AiRecommendation> recommendations) {
        WellnessGoal goal = goals.findByUserId(userId).orElseGet(() -> {
            WellnessGoal created = new WellnessGoal();
            created.setUserId(userId);
            created.setCreatedAt(Instant.now());
            return created;
        });
        Map<String, String> sources = new LinkedHashMap<>(goal.getTargetSources());
        List<String> applied = new ArrayList<>();
        List<String> skipped = new ArrayList<>();

        for (WellnessGoalDtos.AiRecommendation rec : recommendations == null
                ? List.<WellnessGoalDtos.AiRecommendation>of() : recommendations) {
            String metric = rec == null ? null : rec.metric();
            Integer value = rec == null ? null : rec.value();
            String problem = validate(metric, value);
            if (problem != null) {
                skipped.add((metric == null ? "unknown" : metric) + ": " + problem);
                continue;
            }
            Integer current = currentTarget(goal, metric);
            if (current != null && !"AI_RECOMMENDED".equals(sources.get(metric))) {
                skipped.add(metric + ": you already set this target; it was not changed");
                continue;
            }
            setTarget(goal, metric, value);
            sources.put(metric, "AI_RECOMMENDED");
            applied.add(metric + "=" + value);
        }

        goal.setTargetSources(sources);
        goal.setUpdatedAt(Instant.now());
        goals.save(goal);
        return new WellnessGoalDtos.ApplyRecommendationsResponse(
                overview(userId), applied, skipped);
    }

    private static String validate(String metric, Integer value) {
        if (metric == null || value == null) {
            return "metric and value are required";
        }
        return switch (metric) {
            case "dailySteps" -> value >= 500 && value <= 100_000
                    ? null : "must be between 500 and 100000";
            case "dailyActiveMinutes" -> value >= 1 && value <= 600
                    ? null : "must be between 1 and 600";
            case "weeklyWorkoutMinutes" -> value >= 1 && value <= 2_000
                    ? null : "must be between 1 and 2000";
            case "dailySleepMinutes" -> value >= 60 && value <= 960
                    ? null : "must be between 60 and 960";
            case "dailyHydrationMl" -> value >= 250 && value <= 10_000
                    ? null : "must be between 250 and 10000";
            default -> "unsupported metric";
        };
    }

    private static Integer currentTarget(WellnessGoal goal, String metric) {
        return switch (metric) {
            case "dailySteps" -> goal.getDailySteps();
            case "dailyActiveMinutes" -> goal.getDailyActiveMinutes();
            case "weeklyWorkoutMinutes" -> goal.getWeeklyWorkoutMinutes();
            case "dailySleepMinutes" -> goal.getDailySleepMinutes();
            case "dailyHydrationMl" -> goal.getDailyHydrationMl();
            default -> null;
        };
    }

    private static void setTarget(WellnessGoal goal, String metric, Integer value) {
        switch (metric) {
            case "dailySteps" -> goal.setDailySteps(value);
            case "dailyActiveMinutes" -> goal.setDailyActiveMinutes(value);
            case "weeklyWorkoutMinutes" -> goal.setWeeklyWorkoutMinutes(value);
            case "dailySleepMinutes" -> goal.setDailySleepMinutes(value);
            case "dailyHydrationMl" -> goal.setDailyHydrationMl(value);
            default -> {
                // validate() already rejected unknown metrics.
            }
        }
    }

    private static void putSource(Map<String, String> sources, String metric, Integer value) {
        if (value != null) {
            sources.put(metric, "USER");
        }
    }

    private static String targetSource(WellnessGoal goal, String metric) {
        if (goal == null) {
            return null;
        }
        Integer target = currentTarget(goal, metric);
        if (target == null) {
            return null;
        }
        // Legacy documents predate provenance: treat them as user-entered.
        return goal.getTargetSources().getOrDefault(metric, "USER");
    }

    // ── progress ───────────────────────────────────────────────────────────

    private WellnessGoalDtos.GoalProgress dailyActivityProgress(
            String userId, LocalDate today, Integer target, String targetSource) {
        Optional<DailyActivity> activity = dailyActivity.findByUserIdAndDate(userId, today);
        Integer steps = activity.map(DailyActivity::getSteps).orElse(null);
        return progress("steps", "Daily steps", "steps", "day", target,
                steps == null ? null : steps.doubleValue(), steps != null,
                steps == null ? "No step data recorded today" : null, "DEVICE", targetSource);
    }

    private WellnessGoalDtos.GoalProgress activeMinutesProgress(
            String userId, LocalDate today, Integer target, String targetSource) {
        Optional<DailyActivity> activity = dailyActivity.findByUserIdAndDate(userId, today);
        Integer active = activity.map(DailyActivity::getActiveMinutes).orElse(null);
        return progress("activeMinutes", "Active minutes", "min", "day", target,
                active == null ? null : active.doubleValue(), active != null,
                active == null ? "Active minutes were not reported" : null, "DEVICE",
                targetSource);
    }

    private WellnessGoalDtos.GoalProgress sleepProgress(
            String userId, LocalDate today, Integer target, String targetSource) {
        Optional<SleepSession> session = sleepSessions.findFirstByUserIdOrderByStartTimeDesc(userId);
        boolean todaySleep = session.map(row -> today.equals(row.getDate())).orElse(false);
        Double minutes = todaySleep && session.get().getDurationMillis() != null
                ? session.get().getDurationMillis() / 60_000d : null;
        return progress("sleep", "Sleep", "min", "day", target, minutes, minutes != null,
                minutes == null ? "No sleep session recorded for today" : null, "DEVICE",
                targetSource);
    }

    private WellnessGoalDtos.GoalProgress hydrationProgress(
            String userId, LocalDate today, Integer target, String targetSource) {
        Double total = hydration.todayTotalMl(userId, today);
        return progress("hydration", "Hydration", "ml", "day", target, total, total != null,
                total == null ? "Nothing logged today" : null, "USER_ENTERED", targetSource);
    }

    private WellnessGoalDtos.GoalProgress workoutProgress(
            String userId, LocalDate today, Integer target, String targetSource) {
        Instant from = today.minusDays(6).atStartOfDay(zone()).toInstant();
        List<ExerciseSession> rows = exerciseSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                        userId, from, Instant.now());
        long millis = 0;
        int counted = 0;
        for (ExerciseSession row : rows) {
            if (row.getDurationMillis() != null) {
                millis += row.getDurationMillis();
                counted++;
            }
        }
        Double minutes = counted == 0 ? null : millis / 60_000d;
        return progress("workoutMinutes", "Workout minutes", "min", "last_7_days", target,
                minutes, counted > 0,
                counted == 0 ? "No workouts recorded in the last 7 days" : null, "DEVICE",
                targetSource);
    }

    private WellnessGoalDtos.GoalProgress progress(
            String metric, String label, String unit, String period, Integer target,
            Double current, boolean dataAvailable, String note, String source,
            String targetSource) {
        if (target == null) {
            return new WellnessGoalDtos.GoalProgress(metric, label, unit, period, null,
                    current, null, null, null, dataAvailable, source,
                    dataAvailable ? note : (note == null ? "No goal set" : note),
                    null);
        }
        if (!dataAvailable || current == null) {
            return new WellnessGoalDtos.GoalProgress(metric, label, unit, period, target,
                    null, (double) target, null, null, false, source, note,
                    targetSource);
        }
        double remaining = Math.max(0d, target - current);
        double ratio = Math.round((current / target) * 1000d) / 1000d;
        return new WellnessGoalDtos.GoalProgress(metric, label, unit, period, target,
                current, remaining, ratio, current >= target, true, source, note,
                targetSource);
    }

    // ── streaks ────────────────────────────────────────────────────────────

    private WellnessGoalDtos.StreakResult streak(
            String userId, LocalDate today, String metric, Integer target) {
        if (target == null) {
            return new WellnessGoalDtos.StreakResult(metric, 0, 0, 0, 0, "No goal set");
        }
        LocalDate from = today.minusDays(STREAK_WINDOW_DAYS);
        Map<LocalDate, Double> values = metricValues(userId, from, today, metric);
        int daysWithData = values.size();
        int current = 0;
        LocalDate cursor = today.minusDays(1); // today is still in progress
        while (!cursor.isBefore(from)) {
            Double value = values.get(cursor);
            if (value == null) {
                break;
            }
            if (value >= target) {
                current++;
                cursor = cursor.minusDays(1);
            } else {
                break;
            }
        }
        int longest = 0;
        int run = 0;
        LocalDate day = from;
        while (!day.isAfter(today)) {
            Double value = values.get(day);
            if (value != null && value >= target) {
                run++;
                longest = Math.max(longest, run);
            } else {
                run = 0;
            }
            day = day.plusDays(1);
        }
        return new WellnessGoalDtos.StreakResult(metric, current, longest,
                STREAK_WINDOW_DAYS, daysWithData,
                "Streaks count consecutive days with recorded data that met the goal and "
                        + "exclude the current in-progress day.");
    }

    private Map<LocalDate, Double> metricValues(
            String userId, LocalDate from, LocalDate to, String metric) {
        Map<LocalDate, Double> values = new LinkedHashMap<>();
        switch (metric) {
            case "steps", "activeMinutes" -> {
                for (DailyActivity row : dailyActivity
                        .findByUserIdAndDateBetweenOrderByDateDesc(userId, from, to)) {
                    Double value = "steps".equals(metric)
                            ? (row.getSteps() == null ? null : row.getSteps().doubleValue())
                            : (row.getActiveMinutes() == null ? null
                                    : row.getActiveMinutes().doubleValue());
                    if (value != null) {
                        values.put(row.getDate(), value);
                    }
                }
            }
            case "sleep" -> {
                // Sleep is attributed to the wake day, so the first requested
                // day's overnight session starts the day before: reach one
                // extra day back. Sessions waking the same day are added
                // together (a nap plus the main sleep), matching the trends
                // and pattern engines.
                for (SleepSession row : sleepSessions
                        .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                                userId, from.minusDays(1).atStartOfDay(zone()).toInstant(),
                                to.plusDays(1).atStartOfDay(zone()).toInstant())) {
                    if (row.getDate() != null && !row.getDate().isBefore(from)
                            && !row.getDate().isAfter(to) && row.getDurationMillis() != null) {
                        values.merge(row.getDate(), row.getDurationMillis() / 60_000d,
                                Double::sum);
                    }
                }
            }
            case "hydration" -> {
                for (LocalDate day = from; !day.isAfter(to); day = day.plusDays(1)) {
                    Double total = hydration.todayTotalMl(userId, day);
                    if (total != null) {
                        values.put(day, total);
                    }
                }
            }
            default -> {
                // Unknown metric: no streak data.
            }
        }
        return values;
    }

    private static ZoneId zone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }
}
