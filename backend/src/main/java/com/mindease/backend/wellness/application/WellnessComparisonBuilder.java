package com.mindease.backend.wellness.application;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.stereotype.Component;

import com.mindease.backend.wellness.domain.WellnessAnalysisRecord;
import com.mindease.backend.wellness.dto.WellnessComparisonDto;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

/**
 * Diffs the current metric set against the previous stored analysis.
 *
 * <p>Deliberately pure and deterministic: the "what improved / what declined"
 * answer is arithmetic over the two stored snapshots, so it can be trusted and
 * tested. The AI service only rephrases this result, it never decides it.</p>
 */
@Component
public class WellnessComparisonBuilder {

    /** Metrics where a larger number is the better outcome. */
    private static final Set<String> HIGHER_IS_BETTER = Set.of(
            "wellness_score", "lifestyle_score", "mood_score",
            "steps_avg", "active_minutes_avg", "sleep_hours_avg",
            "hydration_ml_avg", "spo2_avg", "hrv_avg",
            "activity_days", "sleep_days", "mood_checkins");

    /** Metrics where a smaller number is the better outcome. */
    private static final Set<String> LOWER_IS_BETTER = Set.of(
            "stress_level", "resting_hr_avg", "days_since_assessment");

    /** Why a change in each aspect usually happens, in plain language. */
    private static final Map<String, String> HABIT_HINTS = buildHabitHints();

    private static final double RELATIVE_TOLERANCE = 0.02;
    private static final double ABSOLUTE_TOLERANCE = 0.5;

    public WellnessComparisonDto build(WellnessAnalysisRecord previous,
                                       List<WellnessMetricDto> current) {
        if (previous == null || previous.getMetrics() == null
                || previous.getMetrics().isEmpty()) {
            return WellnessComparisonDto.firstAnalysis();
        }

        Map<String, Double> before = previous.getMetrics();
        List<WellnessComparisonDto.Change> changes = new ArrayList<>();
        List<String> improved = new ArrayList<>();
        List<String> declined = new ArrayList<>();
        List<String> unchanged = new ArrayList<>();
        List<String> habitInsights = new ArrayList<>();

        for (WellnessMetricDto metric : current) {
            Double oldValue = before.get(metric.key());
            if (oldValue == null) {
                continue;
            }
            double oldNumber = oldValue;
            double newNumber = metric.value();

            String label = metric.label() == null || metric.label().isBlank()
                    ? previous.getMetricLabels() != null
                            ? previous.getMetricLabels().getOrDefault(metric.key(), metric.key())
                            : metric.key()
                    : metric.label();

            String direction = direction(metric.key(), oldNumber, newNumber);
            changes.add(new WellnessComparisonDto.Change(
                    label,
                    format(oldNumber, metric.unit()),
                    format(newNumber, metric.unit()),
                    direction,
                    HABIT_HINTS.getOrDefault(metric.key(),
                            "Compared with your previous analysis.")));

            switch (direction) {
                case "IMPROVED" -> improved.add(label.toLowerCase());
                case "DECLINED" -> declined.add(label.toLowerCase());
                default -> unchanged.add(label.toLowerCase());
            }

            String hint = HABIT_HINTS.get(metric.key());
            if (hint != null && !"UNCHANGED".equals(direction)) {
                habitInsights.add(hint);
            }
        }

        long days = previous.getAnalyzedAt() == null ? 0
                : Math.max(0, Duration.between(previous.getAnalyzedAt(), Instant.now()).toDays());

        String overall;
        if (!improved.isEmpty() && declined.isEmpty()) {
            overall = "IMPROVED";
        } else if (declined.isEmpty() && improved.isEmpty()) {
            overall = "UNCHANGED";
        } else if (improved.isEmpty()) {
            overall = "DECLINED";
        } else {
            overall = "MIXED";
        }

        String summary = summarize(overall, improved, declined, days);

        return new WellnessComparisonDto(
                true,
                previous.getAnalyzedAt(),
                days,
                overall,
                summary,
                List.copyOf(changes),
                List.copyOf(improved),
                List.copyOf(declined),
                List.copyOf(unchanged),
                List.copyOf(dedupe(habitInsights)),
                List.of());
    }

    /**
     * Builds the "what to do next" list from the diff, so the actions always
     * correspond to something that actually changed.
     */
    public List<String> nextActionsFrom(WellnessComparisonDto comparison) {
        List<String> actions = new ArrayList<>();
        if (!comparison.hasPrevious()) {
            return actions;
        }
        if (!comparison.declined().isEmpty()) {
            actions.add("Focus first on " + join(comparison.declined(), 2)
                    + ", which moved in the wrong direction since your last analysis.");
        }
        if (!comparison.improved().isEmpty()) {
            actions.add("Keep doing what improved " + join(comparison.improved(), 2)
                    + " — hold the same routine for another week.");
        }
        if (comparison.declined().isEmpty() && comparison.improved().isEmpty()) {
            actions.add("Nothing changed materially; keep the current routine and "
                    + "re-run the analysis in a few days.");
        }
        return actions;
    }

    private static String format(double value, String unit) {
        String text = Math.abs(value - Math.rint(value)) < 0.001
                ? String.valueOf((long) Math.rint(value))
                : String.format(java.util.Locale.ROOT, "%.1f", value);
        return unit == null || unit.isBlank() ? text : text + " " + unit;
    }

    private static String direction(String key, double oldValue, double newValue) {
        double delta = newValue - oldValue;
        double tolerance = Math.max(Math.abs(oldValue) * RELATIVE_TOLERANCE,
                ABSOLUTE_TOLERANCE);
        if (Math.abs(delta) <= tolerance) {
            return "UNCHANGED";
        }
        // Everything not listed as "lower is better" is treated as a metric
        // where more is better, which is the case for every score and average
        // this app records.
        boolean higherIsBetter = !LOWER_IS_BETTER.contains(key);
        boolean better = higherIsBetter ? delta > 0 : delta < 0;
        return better ? "IMPROVED" : "DECLINED";
    }

    private static String summarize(String overall, List<String> improved,
                                    List<String> declined, long days) {
        String when = days == 0 ? "earlier today" : days == 1 ? "yesterday" : days + " days ago";
        return switch (overall) {
            case "IMPROVED" -> "Improved since your last analysis " + when + ": "
                    + join(improved, 3) + ".";
            case "DECLINED" -> "Lower than your last analysis " + when + ": "
                    + join(declined, 3) + ".";
            case "UNCHANGED" -> "Broadly unchanged since your last analysis " + when + ".";
            default -> "Mixed since your last analysis " + when + " — up: "
                    + join(improved, 2) + "; down: " + join(declined, 2) + ".";
        };
    }

    private static String join(List<String> values, int limit) {
        if (values.isEmpty()) {
            return "";
        }
        List<String> slice = values.size() > limit ? values.subList(0, limit) : values;
        if (slice.size() == 1) {
            return slice.get(0);
        }
        String head = String.join(", ", slice.subList(0, slice.size() - 1));
        return head + " and " + slice.get(slice.size() - 1);
    }

    private static List<String> dedupe(List<String> values) {
        return new ArrayList<>(new java.util.LinkedHashSet<>(values));
    }

    private static Map<String, String> buildHabitHints() {
        Map<String, String> hints = new LinkedHashMap<>();
        hints.put("sleep_hours_avg",
                "Sleep duration usually follows your wind-down time and wake-time consistency.");
        hints.put("steps_avg",
                "Daily steps tend to track how much walking you fit around your usual routine.");
        hints.put("active_minutes_avg",
                "Active minutes depend on whether you break up long sitting during the day.");
        hints.put("hydration_ml_avg",
                "Hydration follows how evenly you spread drinks through the day rather than one large one.");
        hints.put("stress_level",
                "Stress tracks how much recovery time and breathing space you gave yourself.");
        hints.put("wellness_score",
                "Self-reported wellness moves with sleep, stress and daily check-in consistency.");
        hints.put("lifestyle_score",
                "Lifestyle score follows routine consistency across sleep, movement and meals.");
        hints.put("resting_hr_avg",
                "Resting heart rate responds to sleep, stress and recent activity.");
        hints.put("hrv_avg",
                "Heart-rate variability is sensitive to stress and recovery.");
        hints.put("spo2_avg",
                "Blood oxygen readings vary with sleep and measurement conditions.");
        hints.put("mood_checkins",
                "More regular check-ins make every trend more reliable.");
        return java.util.Collections.unmodifiableMap(hints);
    }
}
