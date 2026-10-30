package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.mindease.backend.features.checkin.domain.DailyCheckin;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.SleepSession;

/**
 * The pattern engine is pure and deterministic, so every claim it can make is
 * pinned here. It must never emit a pattern without enough real history, never
 * reuse stale data, and never describe a correlation as a cause.
 */
class MindBodyPatternEngineTest {

    private static final String USER = "user-a";
    private static final LocalDate TODAY = LocalDate.of(2026, 10, 25);
    private static final int WINDOW = 14;

    private final MindBodyPatternEngine engine = new MindBodyPatternEngine();

    // ── fixtures ───────────────────────────────────────────────────────────

    private DailyActivity activity(LocalDate date, Integer steps) {
        DailyActivity row = new DailyActivity();
        row.setUserId(USER);
        row.setDate(date);
        row.setSteps(steps);
        row.setActiveMinutes(steps == null ? null : Math.min(120, steps / 200));
        return row;
    }

    private SleepSession sleep(LocalDate date, long minutes) {
        SleepSession row = new SleepSession();
        row.setUserId(USER);
        row.setDate(date);
        row.setDurationMillis(minutes * 60_000L);
        return row;
    }

    private DailyCheckin checkin(LocalDate date, int mood) {
        DailyCheckin row = new DailyCheckin();
        row.setUserId(USER);
        row.setDate(date);
        row.setMood(mood);
        return row;
    }

    private MindBodyPatternEngine.WellnessContext context(
            List<DailyActivity> activity, List<SleepSession> sleep,
            Map<LocalDate, Double> hydration, List<DailyCheckin> checkins,
            Integer hydrationTarget) {
        return new MindBodyPatternEngine.WellnessContext(
                TODAY, WINDOW, activity, sleep, hydration, checkins,
                Map.of(), Map.of(), hydrationTarget, 480);
    }

    /** Baseline days occupy today-4 .. today-13; recent days are today-1 .. today-3. */
    private static LocalDate baselineDay(int index) {
        return TODAY.minusDays(4 + index);
    }

    private static LocalDate recentDay(int index) {
        return TODAY.minusDays(1L + index);
    }

    // ── insufficient / stale data ──────────────────────────────────────────

    @Test
    void emptyContext_suppressesEveryConclusion() {
        var result = engine.evaluate(context(List.of(), List.of(), Map.of(), List.of(), null));

        assertThat(result.sufficientData()).isFalse();
        assertThat(result.insights()).hasSize(1);
        assertThat(result.insights().get(0).id()).isEqualTo("insufficient_recent_data");
        assertThat(result.insights().get(0).evidence()).isEmpty();
        assertThat(result.recommendations()).isEmpty();
        assertThat(result.limitations()).anyMatch(note -> note.contains("stale"));
    }

    @Test
    void staleData_isNotReused() {
        List<DailyActivity> old = List.of(activity(TODAY.minusDays(12), 9000));
        var result = engine.evaluate(context(old, List.of(), Map.of(), List.of(), null));

        assertThat(result.sufficientData()).isFalse();
        assertThat(result.insights().get(0).id()).isEqualTo("insufficient_recent_data");
    }

    @Test
    void tooFewBaselineDays_doesNotProduceAPattern() {
        List<DailyActivity> activity = new ArrayList<>();
        activity.add(activity(baselineDay(0), 9000));
        activity.add(activity(baselineDay(1), 9000));
        for (int i = 0; i < 3; i++) {
            activity.add(activity(recentDay(i), 1000));
        }

        var result = engine.evaluate(context(activity, List.of(), Map.of(), List.of(), null));

        assertThat(result.insights())
                .noneMatch(item -> "activity_below_baseline".equals(item.id()));
    }

    // ── single-source patterns ─────────────────────────────────────────────

    @Test
    void sleepBelowBaseline_producesEvidenceAndSupportiveRecommendation() {
        List<SleepSession> sleep = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            sleep.add(sleep(baselineDay(i), 480));
        }
        for (int i = 0; i < 3; i++) {
            sleep.add(sleep(recentDay(i), 360));
        }

        var result = engine.evaluate(context(List.of(), sleep, Map.of(), List.of(), null));
        var insight = result.insights().stream()
                .filter(item -> "sleep_below_baseline".equals(item.id())).findFirst().orElseThrow();

        assertThat(insight.severity()).isEqualTo("ATTENTION");
        assertThat(insight.evidence()).hasSize(1);
        assertThat(insight.evidence().get(0).current()).isEqualTo(360d);
        assertThat(insight.evidence().get(0).baseline()).isEqualTo(480d);
        assertThat(insight.disclaimer()).containsIgnoringCase("not");
        assertThat(result.recommendations())
                .anyMatch(rec -> "sleep_wind_down".equals(rec.id()));
        assertThat(result.recommendations())
                .noneMatch(rec -> rec.description().toLowerCase().contains("restrict"));
    }

    @Test
    void flatActivity_doesNotTriggerADipPattern() {
        List<DailyActivity> activity = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            activity.add(activity(baselineDay(i), 8000));
        }
        for (int i = 0; i < 3; i++) {
            activity.add(activity(recentDay(i), 7800));
        }

        var result = engine.evaluate(context(activity, List.of(), Map.of(), List.of(), null));

        assertThat(result.insights())
                .noneMatch(item -> "activity_below_baseline".equals(item.id()));
        assertThat(result.insights())
                .anyMatch(item -> "no_pattern_detected".equals(item.id()));
    }

    @Test
    void hydrationPattern_requiresAUserTarget() {
        Map<LocalDate, Double> hydration = new LinkedHashMap<>();
        for (int i = 0; i < 7; i++) {
            hydration.put(TODAY.minusDays(i + 1), i < 3 ? 500d : 1800d);
        }

        var withoutTarget = engine.evaluate(
                context(List.of(), List.of(), hydration, List.of(), null));
        var withTarget = engine.evaluate(
                context(List.of(), List.of(), hydration, List.of(), 2000));

        assertThat(withoutTarget.insights())
                .noneMatch(item -> "hydration_below_target".equals(item.id()));
        assertThat(withTarget.insights())
                .anyMatch(item -> "hydration_below_target".equals(item.id()));
    }

    @Test
    void elevatedRestingHeartRate_isDescribedAsMultiFactor() {
        Map<LocalDate, Double> resting = new LinkedHashMap<>();
        for (int i = 0; i < 4; i++) {
            resting.put(baselineDay(i), 60d);
        }
        for (int i = 0; i < 3; i++) {
            resting.put(recentDay(i), 70d);
        }
        var context = new MindBodyPatternEngine.WellnessContext(
                TODAY, WINDOW, List.of(), List.of(), Map.of(), List.of(),
                resting, Map.of(), null, null);

        var result = engine.evaluate(context);
        var insight = result.insights().stream()
                .filter(item -> "resting_hr_elevated".equals(item.id())).findFirst().orElseThrow();

        assertThat(insight.summary()).containsIgnoringCase("stress");
        assertThat(insight.summary()).doesNotContainIgnoringCase("you are ill");
    }

    // ── cross-domain patterns ──────────────────────────────────────────────

    @Test
    void lowMoodAndShortSleep_coOccurrenceNeverClaimsCausation() {
        List<SleepSession> sleep = new ArrayList<>();
        List<DailyCheckin> checkins = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            sleep.add(sleep(baselineDay(i), 480));
            checkins.add(checkin(baselineDay(i), 4));
        }
        for (int i = 0; i < 3; i++) {
            sleep.add(sleep(recentDay(i), 360));
            checkins.add(checkin(recentDay(i), 2));
        }

        var result = engine.evaluate(context(List.of(), sleep, Map.of(), checkins, null));
        var insight = result.insights().stream()
                .filter(item -> "mood_sleep_cooccurrence".equals(item.id()))
                .findFirst().orElseThrow();

        assertThat(insight.evidence()).hasSize(2);
        assertThat(insight.summary()).containsIgnoringCase("cannot show");
        assertThat(insight.severity()).isEqualTo("INFO");
    }

    @Test
    void steadySleep_isOnlyReportedWhenThereAreEnoughNights() {
        List<SleepSession> sleep = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            sleep.add(sleep(TODAY.minusDays(i + 1), 470));
        }

        var result = engine.evaluate(context(List.of(), sleep, Map.of(), List.of(), null));

        assertThat(result.insights()).anyMatch(item -> "sleep_steady".equals(item.id()));
    }

    // ── output hygiene ─────────────────────────────────────────────────────

    @Test
    void everyInsightCarriesCoverageAndDisclaimer() {
        List<SleepSession> sleep = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            sleep.add(sleep(baselineDay(i), 480));
        }
        for (int i = 0; i < 3; i++) {
            sleep.add(sleep(recentDay(i), 300));
        }

        var result = engine.evaluate(context(List.of(), sleep, Map.of(), List.of(), null));

        assertThat(result.insights()).isNotEmpty();
        assertThat(result.insights()).allSatisfy(insight -> {
            assertThat(insight.coverage()).isNotNull();
            assertThat(insight.coverage().windowDays()).isEqualTo(WINDOW);
            assertThat(insight.disclaimer()).isEqualTo(MindBodyPatternEngine.DISCLAIMER);
        });
        assertThat(result.coverage().missingSources()).contains("STEPS", "HYDRATION", "MOOD");
    }

    @Test
    void recommendationsAreDeduplicatedAndBounded() {
        List<SleepSession> sleep = new ArrayList<>();
        List<DailyActivity> activity = new ArrayList<>();
        Map<LocalDate, Double> hydration = new LinkedHashMap<>();
        List<DailyCheckin> checkins = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            sleep.add(sleep(baselineDay(i), 480));
            activity.add(activity(baselineDay(i), 9000));
            hydration.put(baselineDay(i), 1800d);
            checkins.add(checkin(baselineDay(i), 4));
        }
        for (int i = 0; i < 3; i++) {
            sleep.add(sleep(recentDay(i), 300));
            activity.add(activity(recentDay(i), 2000));
            hydration.put(recentDay(i), 400d);
            checkins.add(checkin(recentDay(i), 2));
        }

        var result = engine.evaluate(
                context(activity, sleep, hydration, checkins, 2000));

        assertThat(result.recommendations()).hasSizeLessThanOrEqualTo(4);
        assertThat(result.recommendations()).extracting(rec -> rec.id())
                .doesNotHaveDuplicates();
        assertThat(result.recommendations())
                .allSatisfy(rec -> assertThat(rec.description()).isNotBlank());
    }

    @Test
    void weightIsNotPartOfTheContextByDesign() {
        // Guard rail: pattern inference has no weight input, so it cannot make
        // unsupported body-related claims.
        assertThat(MindBodyPatternEngine.WellnessContext.class.getRecordComponents())
                .extracting(java.lang.reflect.RecordComponent::getName)
                .doesNotContain("weightKg", "bodyFat", "bmi");
    }
}
