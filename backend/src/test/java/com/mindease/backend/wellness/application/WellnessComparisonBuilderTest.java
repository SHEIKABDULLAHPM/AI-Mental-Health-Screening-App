package com.mindease.backend.wellness.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.mindease.backend.wellness.domain.WellnessAnalysisRecord;
import com.mindease.backend.wellness.dto.WellnessComparisonDto;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

/**
 * The comparison decides what the app tells a user improved or declined, so it
 * is covered directly rather than only through the HTTP layer.
 */
class WellnessComparisonBuilderTest {

    private final WellnessComparisonBuilder builder = new WellnessComparisonBuilder();

    private static WellnessAnalysisRecord previous(Map<String, Double> metrics) {
        WellnessAnalysisRecord record = new WellnessAnalysisRecord();
        record.setType(WellnessAnalysisRecord.TYPE_PHYSICAL);
        record.setAnalyzedAt(Instant.now().minus(7, ChronoUnit.DAYS));
        record.setMetrics(new LinkedHashMap<>(metrics));
        return record;
    }

    @Test
    void reportsFirstAnalysisWhenNothingWasStored() {
        WellnessComparisonDto comparison = builder.build(null,
                List.of(new WellnessMetricDto("steps_avg", "Daily steps", 5000, "steps")));

        assertThat(comparison.hasPrevious()).isFalse();
        assertThat(comparison.overall()).isEqualTo("FIRST_ANALYSIS");
        assertThat(comparison.summary()).contains("first stored analysis");
        assertThat(comparison.changes()).isEmpty();
    }

    @Test
    void detectsImprovementAndDeclineTogether() {
        // Steps went up, sleep went down: the truthful answer is "mixed".
        WellnessAnalysisRecord before = previous(Map.of(
                "steps_avg", 4000.0,
                "sleep_hours_avg", 8.0));

        WellnessComparisonDto comparison = builder.build(before, List.of(
                new WellnessMetricDto("steps_avg", "Daily steps", 7000, "steps"),
                new WellnessMetricDto("sleep_hours_avg", "Sleep duration", 6, "h")));

        assertThat(comparison.hasPrevious()).isTrue();
        assertThat(comparison.overall()).isEqualTo("MIXED");
        assertThat(comparison.improved()).contains("daily steps");
        assertThat(comparison.declined()).contains("sleep duration");
        assertThat(comparison.summary()).contains("up:").contains("down:");

        WellnessComparisonDto.Change steps = comparison.changes().stream()
                .filter(c -> c.aspect().equals("Daily steps"))
                .findFirst().orElseThrow();
        assertThat(steps.direction()).isEqualTo("IMPROVED");
        assertThat(steps.previous()).isEqualTo("4000 steps");
        assertThat(steps.current()).isEqualTo("7000 steps");
    }

    @Test
    void stressIsJudgedAsLowerIsBetter() {
        WellnessAnalysisRecord before = previous(Map.of("stress_level", 80.0));

        WellnessComparisonDto comparison = builder.build(before,
                List.of(new WellnessMetricDto("stress_level", "Stress level", 40, "/100")));

        assertThat(comparison.overall()).isEqualTo("IMPROVED");
        assertThat(comparison.improved()).contains("stress level");
        assertThat(comparison.declined()).isEmpty();
    }

    @Test
    void smallChangesAreNotReportedAsProgress() {
        WellnessAnalysisRecord before = previous(Map.of("steps_avg", 6000.0));

        WellnessComparisonDto comparison = builder.build(before,
                List.of(new WellnessMetricDto("steps_avg", "Daily steps", 6050, "steps")));

        assertThat(comparison.overall()).isEqualTo("UNCHANGED");
        assertThat(comparison.changes()).hasSize(1);
        assertThat(comparison.changes().get(0).direction()).isEqualTo("UNCHANGED");
    }

    @Test
    void metricsMissingFromHistoryAreIgnoredRatherThanGuessed() {
        WellnessAnalysisRecord before = previous(Map.of("steps_avg", 6000.0));

        WellnessComparisonDto comparison = builder.build(before, List.of(
                new WellnessMetricDto("steps_avg", "Daily steps", 6000, "steps"),
                new WellnessMetricDto("hrv_avg", "HRV", 42, "ms")));

        assertThat(comparison.changes()).hasSize(1);
        assertThat(comparison.changes().get(0).aspect()).isEqualTo("Daily steps");
    }

    @Test
    void nextActionsPointAtTheDecline() {
        WellnessAnalysisRecord before = previous(Map.of("steps_avg", 9000.0));
        WellnessComparisonDto comparison = builder.build(before,
                List.of(new WellnessMetricDto("steps_avg", "Daily steps", 4000, "steps")));

        List<String> actions = builder.nextActionsFrom(comparison);

        assertThat(actions).isNotEmpty();
        assertThat(actions.get(0)).contains("daily steps");
    }
}
