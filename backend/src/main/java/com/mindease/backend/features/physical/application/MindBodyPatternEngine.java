package com.mindease.backend.features.physical.application;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import org.springframework.stereotype.Component;

import com.mindease.backend.features.checkin.domain.DailyCheckin;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.dto.InsightDtos;

/**
 * Deterministic Mind–Body pattern engine.
 *
 * <p>Pure computation over already-authorised, already-aggregated records: no
 * repositories, no network, no LLM. That makes every rule independently
 * testable and keeps AI failures from affecting insight correctness.</p>
 *
 * <p>Design guarantees:</p>
 * <ul>
 *   <li>An insight is only emitted when the window holds enough real data; the
 *       baseline is the user's own preceding days.</li>
 *   <li>Every insight carries the numbers it compared, so the claim can be
 *       audited in the UI.</li>
 *   <li>Patterns describe co-occurrence, never causation, and never diagnose.</li>
 *   <li>Stale data suppresses conclusions instead of reusing old numbers.</li>
 * </ul>
 */
@Component
public class MindBodyPatternEngine {

    static final int DEFAULT_WINDOW_DAYS = 14;
    static final int RECENT_DAYS = 3;
    static final int MIN_BASELINE_POINTS = 3;
    static final int MIN_RECENT_POINTS = 2;
    static final int STALE_AFTER_DAYS = 3;

    static final String DISCLAIMER =
            "These observations describe patterns in your own logged data. They are not "
                    + "medical advice, a diagnosis, or proof that one factor caused another.";

    /** Everything the engine may look at. Maps are keyed by local calendar day. */
    public record WellnessContext(
            LocalDate today,
            int windowDays,
            List<DailyActivity> activity,
            List<SleepSession> sleep,
            Map<LocalDate, Double> hydrationByDay,
            List<DailyCheckin> checkins,
            Map<LocalDate, Double> restingHeartRateByDay,
            Map<LocalDate, Double> hrvByDay,
            Integer hydrationTarget,
            Integer sleepTarget) {
    }

    public record Result(
            List<InsightDtos.PatternInsight> insights,
            List<InsightDtos.Recommendation> recommendations,
            InsightDtos.DataCoverage coverage,
            boolean sufficientData,
            List<String> limitations) {
    }

    public Result evaluate(WellnessContext context) {
        LocalDate today = context.today();
        int window = Math.max(context.windowDays(), RECENT_DAYS + MIN_BASELINE_POINTS);
        LocalDate from = today.minusDays(window - 1L);

        Map<LocalDate, Double> steps = new TreeMap<>();
        Map<LocalDate, Double> activeMinutes = new TreeMap<>();
        for (DailyActivity row : context.activity()) {
            if (row.getDate() == null) {
                continue;
            }
            if (row.getSteps() != null) {
                steps.put(row.getDate(), row.getSteps().doubleValue());
            }
            if (row.getActiveMinutes() != null) {
                activeMinutes.put(row.getDate(), row.getActiveMinutes().doubleValue());
            }
        }

        Map<LocalDate, Double> sleepMinutes = new TreeMap<>();
        for (SleepSession row : context.sleep()) {
            if (row.getDate() == null || row.getDurationMillis() == null) {
                continue;
            }
            sleepMinutes.merge(row.getDate(), row.getDurationMillis() / 60_000d, Double::sum);
        }

        Map<LocalDate, Double> mood = new TreeMap<>();
        int checkinCount = 0;
        for (DailyCheckin checkin : context.checkins()) {
            if (checkin.getDate() == null) {
                continue;
            }
            checkinCount++;
            if (checkin.getMood() != null) {
                mood.put(checkin.getDate(), checkin.getMood().doubleValue());
            }
        }

        Map<LocalDate, Double> hydration = context.hydrationByDay() == null
                ? Map.of() : context.hydrationByDay();

        InsightDtos.DataCoverage coverage = new InsightDtos.DataCoverage(
                window,
                countInWindow(steps.keySet(), from, today),
                countInWindow(sleepMinutes.keySet(), from, today),
                countInWindow(hydration.keySet(), from, today),
                checkinCount,
                countInWindow(context.restingHeartRateByDay() == null
                                ? Set.of() : context.restingHeartRateByDay().keySet(),
                        from, today),
                missingSources(steps, sleepMinutes, hydration, mood, today, from));

        // Staleness is judged across every source the engine can reason from,
        // including wearable point metrics — otherwise a user with only
        // resting-HR history would be told their data is stale.
        LocalDate newest = newestDate(steps.keySet(), sleepMinutes.keySet(),
                hydration.keySet(), mood.keySet(),
                context.restingHeartRateByDay() == null
                        ? Set.of() : context.restingHeartRateByDay().keySet(),
                context.hrvByDay() == null ? Set.of() : context.hrvByDay().keySet());
        boolean stale = newest == null || newest.isBefore(today.minusDays(STALE_AFTER_DAYS));
        if (stale) {
            List<InsightDtos.PatternInsight> insights = List.of(new InsightDtos.PatternInsight(
                    "insufficient_recent_data",
                    "Not enough recent data yet",
                    "We have not received activity, sleep, hydration or check-in data in the "
                            + "last few days, so we are not drawing any conclusions.",
                    "INFO",
                    "LOW",
                    List.of(),
                    coverage,
                    DISCLAIMER));
            return new Result(insights, List.of(), coverage, false,
                    List.of("Data is stale or missing; insights are suppressed until new "
                            + "records arrive."));
        }

        List<InsightDtos.PatternInsight> insights = new ArrayList<>();
        List<InsightDtos.Recommendation> recommendations = new ArrayList<>();

        Double sleepBaseline = baseline(sleepMinutes, today, window);
        Stats sleepRecent = recent(sleepMinutes, today);
        boolean sleepPattern = false;
        if (sleepBaseline != null && sleepRecent.count() >= MIN_RECENT_POINTS
                && sleepRecent.value() <= sleepBaseline * 0.85d) {
            sleepPattern = true;
            insights.add(insight(
                    "sleep_below_baseline",
                    "Sleep has been shorter than your baseline",
                    "Over the last " + RECENT_DAYS + " nights you averaged "
                            + minutes(sleepRecent.value()) + " of sleep, below your recent "
                            + window + "-day baseline of " + minutes(sleepBaseline) + ".",
                    "ATTENTION",
                    confidence(sleepRecent.count(), window),
                    List.of(evidence("SLEEP", "sleep_duration", sleepRecent.value(),
                            sleepBaseline, "min", window, sleepRecent.count(), "below_baseline")),
                    coverage));
            recommendations.add(new InsightDtos.Recommendation(
                    "sleep_wind_down",
                    "Protect a wind-down window",
                    "A consistent, screen-free wind-down routine before bed can support sleep. "
                            + "Keep your usual wake time where you can.",
                    "SLEEP",
                    "RULE_ENGINE"));
        }

        Double stepBaseline = baseline(steps, today, window);
        Stats stepRecent = recent(steps, today);
        if (stepBaseline != null && stepRecent.count() >= MIN_RECENT_POINTS
                && stepRecent.value() <= stepBaseline * 0.75d) {
            insights.add(insight(
                    "activity_below_baseline",
                    "Activity has dipped below your baseline",
                    "You averaged " + count(stepRecent.value()) + " steps over the last "
                            + RECENT_DAYS + " days, compared with your baseline of "
                            + count(stepBaseline) + ".",
                    "ATTENTION",
                    confidence(stepRecent.count(), window),
                    List.of(evidence("STEPS", "steps", stepRecent.value(), stepBaseline,
                            "steps", window, stepRecent.count(), "below_baseline")),
                    coverage));
            recommendations.add(new InsightDtos.Recommendation(
                    "gentle_walk",
                    "Try a comfortable walk",
                    "A short, comfortable walk — even 10 minutes — is a low-pressure way to "
                            + "add movement without turning it into a task.",
                    "ACTIVITY",
                    "RULE_ENGINE"));
        }

        Integer hydrationTarget = context.hydrationTarget();
        Double hydrationBaseline = baseline(hydration, today, window);
        Stats hydrationRecent = recent(hydration, today);
        if (hydrationTarget != null && hydrationBaseline != null
                && hydrationRecent.count() >= MIN_RECENT_POINTS
                && hydrationRecent.value() < hydrationTarget * 0.7d) {
            insights.add(insight(
                    "hydration_below_target",
                    "Hydration is below the target you set",
                    "You logged an average of " + millilitres(hydrationRecent.value())
                            + " per day over the last " + RECENT_DAYS + " days, below your "
                            + millilitres(hydrationTarget) + " target.",
                    "INFO",
                    confidence(hydrationRecent.count(), window),
                    List.of(evidence("HYDRATION", "hydration", hydrationRecent.value(),
                            hydrationTarget.doubleValue(), "ml", RECENT_DAYS,
                            hydrationRecent.count(), "below_target")),
                    coverage));
            recommendations.add(new InsightDtos.Recommendation(
                    "hydration_reminder",
                    "Keep water within reach",
                    "A glass of water with meals or after a break is an easy anchor. "
                            + "Your target is yours to adjust.",
                    "HYDRATION",
                    "RULE_ENGINE"));
        }

        Double moodBaseline = baseline(mood, today, window);
        Stats moodRecent = recent(mood, today);
        boolean lowMood = moodBaseline != null && moodRecent.count() >= MIN_RECENT_POINTS
                && moodRecent.value() <= 2.5d;
        if (lowMood) {
            insights.add(insight(
                    "mood_below_usual",
                    "Your recent check-ins are lower than usual",
                    "Your last " + moodRecent.count() + " check-in average is "
                            + oneDecimal(moodRecent.value()) + " out of 5"
                            + (moodBaseline == null ? "" : ", compared with a baseline of "
                                    + oneDecimal(moodBaseline)) + ".",
                    "ATTENTION",
                    confidence(moodRecent.count(), window),
                    List.of(evidence("CHECKIN", "mood", moodRecent.value(), moodBaseline,
                            "1-5", window, moodRecent.count(), "below_baseline")),
                    coverage));
            recommendations.add(new InsightDtos.Recommendation(
                    "breathing_break",
                    "Take a short breathing break",
                    "A few slow breaths can take the edge off a tense moment. Try the "
                            + "4-7-8 pattern for three cycles.",
                    "RELAXATION",
                    "RULE_ENGINE"));
        }

        if (lowMood && sleepPattern) {
            insights.add(insight(
                    "mood_sleep_cooccurrence",
                    "Lower mood and shorter sleep have appeared together",
                    "Your recent check-ins are lower than usual at the same time as your sleep "
                            + "dipping below baseline. These patterns can influence each other, "
                            + "but this data cannot show that one caused the other.",
                    "INFO",
                    confidence(Math.min(sleepRecent.count(), moodRecent.count()), window),
                    List.of(
                            evidence("CHECKIN", "mood", moodRecent.value(), moodBaseline,
                                    "1-5", window, moodRecent.count(), "below_baseline"),
                            evidence("SLEEP", "sleep_duration", sleepRecent.value(),
                                    sleepBaseline, "min", window, sleepRecent.count(),
                                    "below_baseline")),
                    coverage));
        }

        // Positive reinforcement: only when we actually have the nights to prove it.
        if (sleepBaseline != null && sleepMinutes.size() >= 4) {
            int consistent = 0;
            int nights = 0;
            for (int ago = 1; ago <= 5; ago++) {
                Double value = sleepMinutes.get(today.minusDays(ago));
                if (value == null) {
                    continue;
                }
                nights++;
                if (value >= sleepBaseline * 0.9d && value <= sleepBaseline * 1.1d) {
                    consistent++;
                }
            }
            if (nights >= 4 && consistent >= 4) {
                insights.add(insight(
                        "sleep_steady",
                        "Your sleep has been steady",
                        consistent + " of your last " + nights + " nights were within 10% of "
                                + "your recent baseline.",
                        "POSITIVE",
                        confidence(nights, window),
                        List.of(evidence("SLEEP", "sleep_duration", sleepBaseline,
                                sleepBaseline, "min", window, nights, "within_baseline")),
                        coverage));
            }
        }

        Stats restingRecent = recent(context.restingHeartRateByDay(), today);
        Double restingBaseline = baseline(context.restingHeartRateByDay(), today, window);
        if (restingBaseline != null && restingRecent.count() >= MIN_RECENT_POINTS
                && restingRecent.value() >= restingBaseline + 5d) {
            insights.add(insight(
                    "resting_hr_elevated",
                    "Resting heart rate is above your baseline",
                    "Your recent average resting heart rate is "
                            + oneDecimal(restingRecent.value()) + " bpm, about "
                            + oneDecimal(restingRecent.value() - restingBaseline)
                            + " bpm above your baseline. Stress, illness, alcohol and "
                            + "training load can all influence this.",
                    "INFO",
                    confidence(restingRecent.count(), window),
                    List.of(evidence("WEARABLE", "resting_heart_rate", restingRecent.value(),
                            restingBaseline, "bpm", window, restingRecent.count(),
                            "above_baseline")),
                    coverage));
            recommendations.add(new InsightDtos.Recommendation(
                    "recovery_day",
                    "Consider a lighter day",
                    "When your resting heart rate is above your usual range, an easier day and "
                            + "a little extra rest are reasonable options.",
                    "RECOVERY",
                    "RULE_ENGINE"));
        }

        Stats hrvRecent = recent(context.hrvByDay(), today);
        Double hrvBaseline = baseline(context.hrvByDay(), today, window);
        if (hrvBaseline != null && hrvRecent.count() >= MIN_RECENT_POINTS
                && hrvRecent.value() <= hrvBaseline * 0.8d) {
            insights.add(insight(
                    "hrv_below_baseline",
                    "HRV is below your baseline",
                    "Your recent HRV average is " + oneDecimal(hrvRecent.value())
                            + " ms, below your baseline of " + oneDecimal(hrvBaseline)
                            + " ms. HRV varies naturally with sleep, stress and training.",
                    "INFO",
                    confidence(hrvRecent.count(), window),
                    List.of(evidence("WEARABLE", "hrv", hrvRecent.value(), hrvBaseline, "ms",
                            window, hrvRecent.count(), "below_baseline")),
                    coverage));
        }

        if (insights.isEmpty()) {
            insights.add(insight(
                    "no_pattern_detected",
                    "No clear pattern yet",
                    "Your recent activity, sleep and check-ins are within your usual range. "
                            + "Keep logging and we will look again as more data arrives.",
                    "INFO",
                    "LOW",
                    List.of(),
                    coverage));
        }

        List<String> limitations = new ArrayList<>();
        if (coverage.daysWithActivity() < window) {
            limitations.add("Activity coverage: " + coverage.daysWithActivity() + "/"
                    + window + " days.");
        }
        if (coverage.daysWithSleep() < window) {
            limitations.add("Sleep coverage: " + coverage.daysWithSleep() + "/"
                    + window + " nights.");
        }
        if (coverage.daysWithHydration() == 0) {
            limitations.add("No hydration entries in this window.");
        }
        if (coverage.moodCheckins() == 0) {
            limitations.add("No mood check-ins in this window.");
        }
        limitations.add("SpO2 readings are never interpreted as a medical finding.");
        limitations.add("Patterns are descriptive and cannot establish causation.");

        boolean sufficient = insights.stream()
                .anyMatch(item -> !"no_pattern_detected".equals(item.id())
                        && !"insufficient_recent_data".equals(item.id()));
        return new Result(insights, dedupeRecommendations(recommendations),
                coverage, sufficient, limitations);
    }

    // ── statistics ─────────────────────────────────────────────────────────

    private record Stats(double value, int count) {
    }

    private static Stats recent(Map<LocalDate, Double> values, LocalDate today) {
        if (values == null || values.isEmpty()) {
            return new Stats(0d, 0);
        }
        double sum = 0;
        int count = 0;
        for (int ago = 1; ago <= RECENT_DAYS; ago++) {
            Double value = values.get(today.minusDays(ago));
            if (value != null) {
                sum += value;
                count++;
            }
        }
        return new Stats(count == 0 ? 0d : sum / count, count);
    }

    private static Double baseline(Map<LocalDate, Double> values, LocalDate today, int window) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        double sum = 0;
        int count = 0;
        for (int ago = RECENT_DAYS + 1; ago <= window; ago++) {
            Double value = values.get(today.minusDays(ago));
            if (value != null) {
                sum += value;
                count++;
            }
        }
        if (count < MIN_BASELINE_POINTS) {
            return null;
        }
        return sum / count;
    }

    // ── builders ───────────────────────────────────────────────────────────

    private static InsightDtos.PatternInsight insight(
            String id, String title, String summary, String severity, String confidence,
            List<InsightDtos.Evidence> evidence, InsightDtos.DataCoverage coverage) {
        return new InsightDtos.PatternInsight(id, title, summary, severity, confidence,
                evidence, coverage, DISCLAIMER);
    }

    private static InsightDtos.Evidence evidence(
            String source, String metric, Double current, Double baseline, String unit,
            int windowDays, int coverageDays, String comparison) {
        return new InsightDtos.Evidence(source, metric,
                round(current), baseline == null ? null : round(baseline), unit,
                windowDays, coverageDays, comparison);
    }

    private static String confidence(int coverageDays, int windowDays) {
        double ratio = windowDays <= 0 ? 0 : (double) coverageDays / windowDays;
        if (ratio >= 0.6) {
            return "MEDIUM";
        }
        return "LOW";
    }

    private static List<InsightDtos.Recommendation> dedupeRecommendations(
            List<InsightDtos.Recommendation> recommendations) {
        Map<String, InsightDtos.Recommendation> unique = new LinkedHashMap<>();
        for (InsightDtos.Recommendation recommendation : recommendations) {
            unique.putIfAbsent(recommendation.id(), recommendation);
        }
        return unique.values().stream().limit(4).toList();
    }

    private static List<String> missingSources(
            Map<LocalDate, Double> steps, Map<LocalDate, Double> sleep,
            Map<LocalDate, Double> hydration, Map<LocalDate, Double> mood,
            LocalDate today, LocalDate from) {
        List<String> missing = new ArrayList<>();
        if (countInWindow(steps.keySet(), from, today) == 0) {
            missing.add("STEPS");
        }
        if (countInWindow(sleep.keySet(), from, today) == 0) {
            missing.add("SLEEP");
        }
        if (countInWindow(hydration.keySet(), from, today) == 0) {
            missing.add("HYDRATION");
        }
        if (countInWindow(mood.keySet(), from, today) == 0) {
            missing.add("MOOD");
        }
        return missing;
    }

    private static LocalDate newestDate(Set<LocalDate>... sets) {
        LocalDate newest = null;
        for (Set<LocalDate> set : sets) {
            for (LocalDate date : set) {
                if (newest == null || date.isAfter(newest)) {
                    newest = date;
                }
            }
        }
        return newest;
    }

    private static int countInWindow(Set<LocalDate> dates, LocalDate from, LocalDate to) {
        int count = 0;
        for (LocalDate date : dates) {
            if (!date.isBefore(from) && !date.isAfter(to)) {
                count++;
            }
        }
        return count;
    }

    private static double round(double value) {
        return Math.round(value * 10d) / 10d;
    }

    private static String oneDecimal(double value) {
        return String.format(java.util.Locale.ROOT, "%.1f", value);
    }

    private static String minutes(double value) {
        long total = Math.round(value);
        long hours = total / 60;
        long mins = total % 60;
        return hours == 0 ? mins + " min" : hours + "h " + mins + "m";
    }

    private static String millilitres(double value) {
        return Math.round(value) + " ml";
    }

    private static String count(double value) {
        return String.format(java.util.Locale.ROOT, "%,d", Math.round(value));
    }
}
