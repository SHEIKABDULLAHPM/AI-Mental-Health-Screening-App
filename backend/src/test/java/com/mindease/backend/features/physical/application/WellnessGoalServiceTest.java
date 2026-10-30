package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

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
 * Goals are optional, progress requires real records, and streaks never invent
 * a day. A missing day is reported as missing, not as a failed goal.
 */
@ExtendWith(MockitoExtension.class)
class WellnessGoalServiceTest {

    private static final String USER = "user-a";
    private static final LocalDate TODAY = LocalDate.now(ZoneOffset.UTC);

    @Mock
    private WellnessGoalRepository goals;
    @Mock
    private DailyActivityRepository dailyActivity;
    @Mock
    private SleepSessionRepository sleepSessions;
    @Mock
    private ExerciseSessionRepository exerciseSessions;
    @Mock
    private HydrationService hydration;

    private WellnessGoalService service;

    @BeforeEach
    void setUp() {
        UserTimeZoneHolder.set("UTC");
        service = new WellnessGoalService(goals, dailyActivity, sleepSessions,
                exerciseSessions, hydration);
        lenient().when(goals.findByUserId(USER)).thenReturn(Optional.empty());
        lenient().when(dailyActivity.findByUserIdAndDate(eq(USER), any()))
                .thenReturn(Optional.empty());
        lenient().when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.empty());
        lenient().when(hydration.todayTotalMl(eq(USER), any())).thenReturn(null);
        lenient().when(exerciseSessions
                        .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(dailyActivity
                        .findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(sleepSessions
                        .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
    }

    @AfterEach
    void tearDown() {
        UserTimeZoneHolder.clear();
    }

    private WellnessGoal goalWith(Integer steps, Integer active, Integer workout,
                                  Integer sleep, Integer water) {
        WellnessGoal goal = new WellnessGoal();
        goal.setUserId(USER);
        goal.setDailySteps(steps);
        goal.setDailyActiveMinutes(active);
        goal.setWeeklyWorkoutMinutes(workout);
        goal.setDailySleepMinutes(sleep);
        goal.setDailyHydrationMl(water);
        return goal;
    }

    @Test
    void overview_withoutConfiguredGoals_leavesTargetsNull() {
        var response = service.overview(USER);

        assertThat(response.customized()).isFalse();
        assertThat(response.goals().dailySteps()).isNull();
        assertThat(response.goals().dailyHydrationMl()).isNull();
        assertThat(response.progress()).hasSize(5);
        assertThat(response.progress())
                .allSatisfy(item -> assertThat(item.target()).isNull());
        // Suggested defaults are separate from the user's (absent) goal.
        assertThat(response.suggestedDefaults().dailySteps()).isEqualTo(7000);
        assertThat(response.guidance()).isNotEmpty();
    }

    @Test
    void stepProgress_usesTodayActivityAndReportsCompletion() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(8000, null, null, null, null)));
        DailyActivity activity = new DailyActivity();
        activity.setDate(TODAY);
        activity.setSteps(6000);
        when(dailyActivity.findByUserIdAndDate(USER, TODAY)).thenReturn(Optional.of(activity));

        var response = service.overview(USER);
        var steps = response.progress().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.target()).isEqualTo(8000);
        assertThat(steps.current()).isEqualTo(6000d);
        assertThat(steps.remaining()).isEqualTo(2000d);
        assertThat(steps.met()).isFalse();
        assertThat(steps.dataAvailable()).isTrue();
        assertThat(steps.progress()).isEqualTo(0.75d);
    }

    @Test
    void stepProgress_withoutData_isUnknownNotZero() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(8000, null, null, null, null)));

        var steps = service.overview(USER).progress().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.dataAvailable()).isFalse();
        assertThat(steps.current()).isNull();
        assertThat(steps.progress()).isNull();
        assertThat(steps.met()).isNull();
        assertThat(steps.note()).containsIgnoringCase("No step data");
    }

    @Test
    void hydrationStreak_countsConsecutiveMetDaysAndExcludesToday() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(null, null, null, null, 2000)));
        Map<LocalDate, Double> totals = new HashMap<>();
        totals.put(TODAY.minusDays(1), 2500d);
        totals.put(TODAY.minusDays(2), 2100d);
        totals.put(TODAY.minusDays(3), 1800d); // missed target -> breaks the streak
        totals.put(TODAY.minusDays(4), 2400d);
        // Today's own (partial) value must not be counted either way.
        totals.put(TODAY, 300d);
        when(hydration.todayTotalMl(eq(USER), any())).thenAnswer(invocation ->
                totals.get(invocation.getArgument(1, LocalDate.class)));

        var streak = service.overview(USER).streaks().get("hydration");

        assertThat(streak).isNotNull();
        assertThat(streak.currentStreak()).isEqualTo(2);
        assertThat(streak.longestStreak()).isEqualTo(2);
        assertThat(streak.daysWithData()).isEqualTo(5);
        assertThat(streak.note()).containsIgnoringCase("in-progress");
    }

    @Test
    void hydrationStreak_isZeroWithoutDaysWithData() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(null, null, null, null, 2000)));

        var streak = service.overview(USER).streaks().get("hydration");

        assertThat(streak.currentStreak()).isZero();
        assertThat(streak.daysWithData()).isZero();
    }

    @Test
    void sleepProgress_requiresASessionForToday() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(null, null, null, 480, null)));
        SleepSession session = new SleepSession();
        session.setDate(TODAY.minusDays(1));
        session.setDurationMillis(25_200_000L);
        when(sleepSessions.findFirstByUserIdOrderByStartTimeDesc(USER))
                .thenReturn(Optional.of(session));

        var sleep = service.overview(USER).progress().stream()
                .filter(item -> "sleep".equals(item.metric())).findFirst().orElseThrow();

        // Last night's session belongs to yesterday, so "today" is still unknown.
        assertThat(sleep.dataAvailable()).isFalse();
        assertThat(sleep.current()).isNull();
        assertThat(sleep.note()).containsIgnoringCase("today");
    }

    @Test
    void workoutProgress_sumsOnlyTheLastSevenDays() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(null, null, 150, null, null)));
        ExerciseSession first = new ExerciseSession();
        first.setDurationMillis(1_800_000L);
        ExerciseSession second = new ExerciseSession();
        second.setDurationMillis(1_200_000L);
        when(exerciseSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(eq(USER), any(), any()))
                .thenReturn(List.of(first, second));

        var workout = service.overview(USER).progress().stream()
                .filter(item -> "workoutMinutes".equals(item.metric())).findFirst().orElseThrow();

        assertThat(workout.current()).isEqualTo(50d);
        assertThat(workout.target()).isEqualTo(150);
        assertThat(workout.met()).isFalse();
        assertThat(workout.period()).isEqualTo("last_7_days");
    }

    @Test
    void update_persistsEveryFieldAndClearsOmittedOnes() {
        WellnessGoal existing = goalWith(9000, 45, 180, 480, 2200);
        when(goals.findByUserId(USER)).thenReturn(Optional.of(existing));

        var response = service.update(USER, new WellnessGoalDtos.GoalRequest(
                10_000, null, 200, 450, 2500));

        assertThat(existing.getDailySteps()).isEqualTo(10_000);
        assertThat(existing.getDailyActiveMinutes()).isNull();
        assertThat(existing.getWeeklyWorkoutMinutes()).isEqualTo(200);
        assertThat(existing.getDailySleepMinutes()).isEqualTo(450);
        assertThat(existing.getDailyHydrationMl()).isEqualTo(2500);
        assertThat(response.goals().dailySteps()).isEqualTo(10_000);
    }

    @Test
    void progress_isCappedSoOverAchievementDoesNotReadAsFailure() {
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(5000, null, null, null, null)));
        DailyActivity activity = new DailyActivity();
        activity.setDate(TODAY);
        activity.setSteps(12_000);
        when(dailyActivity.findByUserIdAndDate(USER, TODAY)).thenReturn(Optional.of(activity));

        var steps = service.overview(USER).progress().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.met()).isTrue();
        assertThat(steps.remaining()).isZero();
        assertThat(steps.current()).isEqualTo(12_000d);
    }

    @Test
    void timestampsAreNeverUsedToFakeActivity() {
        // Regression guard: an Instant alone must not produce progress.
        DailyActivity activity = new DailyActivity();
        activity.setDate(TODAY);
        activity.setCreatedAt(Instant.now());
        when(goals.findByUserId(USER))
                .thenReturn(Optional.of(goalWith(5000, null, null, null, null)));
        when(dailyActivity.findByUserIdAndDate(USER, TODAY)).thenReturn(Optional.of(activity));

        var steps = service.overview(USER).progress().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.dataAvailable()).isFalse();
        assertThat(steps.current()).isNull();
    }

    @Test
    void applyAiRecommendations_writesValidTargetAndMarksProvenance() {
        AtomicReference<WellnessGoal> stored = new AtomicReference<>();
        when(goals.findByUserId(USER)).thenAnswer(i -> Optional.ofNullable(stored.get()));
        when(goals.save(any(WellnessGoal.class))).thenAnswer(i -> {
            stored.set(i.getArgument(0));
            return stored.get();
        });

        var response = service.applyAiRecommendations(USER, List.of(
                new WellnessGoalDtos.AiRecommendation("dailySteps", 7500, "gradual"),
                new WellnessGoalDtos.AiRecommendation("dailySleepMinutes", 480, "consistent")));

        assertThat(response.applied()).containsExactly("dailySteps=7500",
                "dailySleepMinutes=480");
        assertThat(response.skipped()).isEmpty();
        assertThat(stored.get().getDailySteps()).isEqualTo(7500);
        assertThat(stored.get().getDailySleepMinutes()).isEqualTo(480);
        assertThat(stored.get().getTargetSources())
                .containsEntry("dailySteps", "AI_RECOMMENDED")
                .containsEntry("dailySleepMinutes", "AI_RECOMMENDED");
        assertThat(response.goals().goals().dailySteps()).isEqualTo(7500);
    }

    @Test
    void applyAiRecommendations_neverOverwritesAUserTarget() {
        WellnessGoal existing = goalWith(9000, null, null, null, null);
        existing.setTargetSources(new HashMap<>(Map.of("dailySteps", "USER")));
        AtomicReference<WellnessGoal> stored = new AtomicReference<>(existing);
        when(goals.findByUserId(USER)).thenAnswer(i -> Optional.ofNullable(stored.get()));
        when(goals.save(any(WellnessGoal.class))).thenAnswer(i -> {
            stored.set(i.getArgument(0));
            return stored.get();
        });

        var response = service.applyAiRecommendations(USER, List.of(
                new WellnessGoalDtos.AiRecommendation("dailySteps", 5000, "less")));

        assertThat(response.applied()).isEmpty();
        assertThat(response.skipped()).hasSize(1);
        assertThat(response.skipped().get(0)).contains("dailySteps");
        assertThat(stored.get().getDailySteps()).isEqualTo(9000);
        assertThat(stored.get().getTargetSources()).containsEntry("dailySteps", "USER");
    }

    @Test
    void applyAiRecommendations_rejectsInvalidAndUnsupportedTargets() {
        AtomicReference<WellnessGoal> stored = new AtomicReference<>();
        when(goals.findByUserId(USER)).thenAnswer(i -> Optional.ofNullable(stored.get()));
        when(goals.save(any(WellnessGoal.class))).thenAnswer(i -> {
            stored.set(i.getArgument(0));
            return stored.get();
        });

        var response = service.applyAiRecommendations(USER, List.of(
                new WellnessGoalDtos.AiRecommendation("dailySteps", 10, "too low"),
                new WellnessGoalDtos.AiRecommendation("bodyFat", 20, "unsupported"),
                new WellnessGoalDtos.AiRecommendation("dailyHydrationMl", 2000, "valid")));

        assertThat(response.applied()).containsExactly("dailyHydrationMl=2000");
        assertThat(response.skipped()).hasSize(2);
        assertThat(stored.get().getDailySteps()).isNull();
        assertThat(stored.get().getDailyHydrationMl()).isEqualTo(2000);
    }
}
