package com.mindease.backend.features.physical.application;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

import org.springframework.stereotype.Service;

import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.HealthMetricType;
import com.mindease.backend.features.physical.domain.HealthReading;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.dto.TrendDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Daily trend series built strictly from stored records.
 *
 * <p>Gaps are gaps: a day with no record is absent from {@code points} and the
 * coverage counters say so. Nothing is interpolated and no baseline is invented
 * — the comparison baseline is the user's own immediately preceding window.</p>
 */
@Service
public class PhysicalTrendService {

    static final int DEFAULT_WINDOW_DAYS = 7;
    static final int MAX_WINDOW_DAYS = 90;

    private final DailyActivityRepository dailyActivity;
    private final SleepSessionRepository sleepSessions;
    private final HealthReadingRepository readings;
    private final HydrationService hydration;

    public PhysicalTrendService(DailyActivityRepository dailyActivity,
                                SleepSessionRepository sleepSessions,
                                HealthReadingRepository readings,
                                HydrationService hydration) {
        this.dailyActivity = dailyActivity;
        this.sleepSessions = sleepSessions;
        this.readings = readings;
        this.hydration = hydration;
    }

    public TrendDtos.TrendsResponse trends(String userId, Integer daysParam) {
        int window = daysParam == null ? DEFAULT_WINDOW_DAYS : daysParam;
        window = Math.min(Math.max(window, 1), MAX_WINDOW_DAYS);
        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        LocalDate from = today.minusDays(window - 1L);
        LocalDate previousFrom = from.minusDays(window);
        LocalDate previousTo = from.minusDays(1);

        List<DailyActivity> currentActivity = dailyActivity
                .findByUserIdAndDateBetweenOrderByDateDesc(userId, from, today);
        List<DailyActivity> previousActivity = dailyActivity
                .findByUserIdAndDateBetweenOrderByDateDesc(userId, previousFrom, previousTo);

        Map<LocalDate, DailyActivity> currentByDate = index(currentActivity);
        Map<LocalDate, DailyActivity> previousByDate = index(previousActivity);

        List<TrendDtos.MetricTrend> metrics = new ArrayList<>();
        metrics.add(activityTrend("steps", "Steps", "steps", "total", currentByDate,
                previousByDate, window, "MEASURED", row ->
                        row.getSteps() == null ? null : row.getSteps().doubleValue()));
        metrics.add(activityTrend("distance", "Distance", "m", "total", currentByDate,
                previousByDate, window, "MEASURED", DailyActivity::getDistanceMeters));
        metrics.add(activityTrend("calories", "Calories", "kcal", "total", currentByDate,
                previousByDate, window, "MEASURED", DailyActivity::getCaloriesKcal));
        metrics.add(activityTrend("activeMinutes", "Active minutes", "min", "total",
                currentByDate, previousByDate, window, "MEASURED", row ->
                        row.getActiveMinutes() == null ? null
                                : row.getActiveMinutes().doubleValue()));

        metrics.add(series("sleepMinutes", "Sleep duration", "min", "total",
                sleepSeries(userId, from, today, zone),
                sleepSeries(userId, previousFrom, previousTo, zone),
                window, "MEASURED",
                "Sessions are attributed to the local wake day."));

        metrics.add(series("hydrationMl", "Hydration", "ml", "total",
                hydrationSeries(userId, from, today), hydrationSeries(userId, previousFrom, previousTo),
                window, "USER_ENTERED",
                "Totals are the sum of logged entries; days without entries are absent."));

        metrics.add(metricTrend("restingHeartRate", "Resting heart rate", "bpm", "average",
                readingSeries(userId, HealthMetricType.RESTING_HEART_RATE, from, today, zone),
                readingSeries(userId, HealthMetricType.RESTING_HEART_RATE, previousFrom, previousTo, zone),
                window, "MEASURED",
                "Only present when the device reports resting heart rate."));
        metrics.add(metricTrend("hrv", "Heart-rate variability", "ms", "average",
                readingSeries(userId, HealthMetricType.HEART_RATE_VARIABILITY, from, today, zone),
                readingSeries(userId, HealthMetricType.HEART_RATE_VARIABILITY, previousFrom, previousTo, zone),
                window, "MEASURED",
                "Only present when the device reports a genuine HRV measure."));
        metrics.add(metricTrend("spo2", "Blood oxygen (SpO2)", "%", "average",
                readingSeries(userId, HealthMetricType.SPO2, from, today, zone),
                readingSeries(userId, HealthMetricType.SPO2, previousFrom, previousTo, zone),
                window, "MEASURED",
                "Only present when the device reports SpO2; not a medical assessment."));

        List<String> coverageNotes = new ArrayList<>();
        for (TrendDtos.MetricTrend metric : metrics) {
            if (metric.daysWithData() == 0) {
                coverageNotes.add(metric.label() + ": no data in this window.");
            } else if (metric.daysWithData() < window) {
                coverageNotes.add(metric.label() + ": " + metric.daysWithData() + " of "
                        + window + " days have data; missing days are not estimated.");
            }
        }
        if (coverageNotes.isEmpty()) {
            coverageNotes.add("All reported metrics have complete data for this window.");
        }

        return new TrendDtos.TrendsResponse(from, today, window, window, metrics,
                coverageNotes);
    }

    // ── builders ───────────────────────────────────────────────────────────

    private TrendDtos.MetricTrend activityTrend(
            String metric, String label, String unit, String aggregation,
            Map<LocalDate, DailyActivity> current, Map<LocalDate, DailyActivity> previous,
            int window, String quality,
            java.util.function.Function<DailyActivity, Double> extractor) {
        Map<LocalDate, Double> currentValues = new TreeMap<>();
        for (Map.Entry<LocalDate, DailyActivity> entry : current.entrySet()) {
            Double value = extractor.apply(entry.getValue());
            if (value != null) {
                currentValues.put(entry.getKey(), value);
            }
        }
        Map<LocalDate, Double> previousValues = new TreeMap<>();
        for (Map.Entry<LocalDate, DailyActivity> entry : previous.entrySet()) {
            Double value = extractor.apply(entry.getValue());
            if (value != null) {
                previousValues.put(entry.getKey(), value);
            }
        }
        return build(metric, label, unit, aggregation, currentValues, previousValues,
                window, quality, "Device daily totals or summed interval records.");
    }

    private TrendDtos.MetricTrend series(
            String metric, String label, String unit, String aggregation,
            Map<LocalDate, Double> current, Map<LocalDate, Double> previous,
            int window, String quality, String note) {
        return build(metric, label, unit, aggregation, current, previous, window, quality, note);
    }

    private TrendDtos.MetricTrend metricTrend(
            String metric, String label, String unit, String aggregation,
            Map<LocalDate, Double> current, Map<LocalDate, Double> previous,
            int window, String quality, String note) {
        return build(metric, label, unit, aggregation, current, previous, window, quality, note);
    }

    private TrendDtos.MetricTrend build(
            String metric, String label, String unit, String aggregation,
            Map<LocalDate, Double> current, Map<LocalDate, Double> previous,
            int window, String quality, String note) {
        List<TrendDtos.TrendPoint> points = new ArrayList<>();
        for (Map.Entry<LocalDate, Double> entry : current.entrySet()) {
            points.add(new TrendDtos.TrendPoint(entry.getKey(),
                    round(entry.getValue()), quality));
        }
        Double average = mean(current.values());
        Double previousAverage = mean(previous.values());
        Double changePercent = null;
        if (average != null && previousAverage != null && previousAverage != 0d) {
            changePercent = round(((average - previousAverage) / previousAverage) * 100d);
        }
        return new TrendDtos.MetricTrend(metric, label, unit, aggregation, points,
                average, previousAverage, changePercent, current.size(), window,
                quality, note);
    }

    private Map<LocalDate, Double> sleepSeries(
            String userId, LocalDate from, LocalDate to, ZoneId zone) {
        Map<LocalDate, Double> byDay = new LinkedHashMap<>();
        // Sleep is attributed to the wake day (SleepSession.date = end date),
        // so a session waking on `from` starts the evening before. The query
        // therefore begins one extra day earlier and the wake-day filter
        // below does the actual window bounding — otherwise the window's
        // first night was silently dropped from the sleep trend.
        List<SleepSession> rows = sleepSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                        userId, from.minusDays(1).atStartOfDay(zone).toInstant(),
                        to.plusDays(1).atStartOfDay(zone).toInstant());
        for (SleepSession row : rows) {
            if (row.getDate() == null || row.getDurationMillis() == null) {
                continue;
            }
            if (row.getDate().isBefore(from) || row.getDate().isAfter(to)) {
                continue;
            }
            byDay.merge(row.getDate(), row.getDurationMillis() / 60_000d, Double::sum);
        }
        return new TreeMap<>(byDay);
    }

    private Map<LocalDate, Double> hydrationSeries(
            String userId, LocalDate from, LocalDate to) {
        Map<LocalDate, Double> byDay = new TreeMap<>();
        for (LocalDate day = from; !day.isAfter(to); day = day.plusDays(1)) {
            Double total = hydration.todayTotalMl(userId, day);
            if (total != null) {
                byDay.put(day, total);
            }
        }
        return byDay;
    }

    private Map<LocalDate, Double> readingSeries(
            String userId, HealthMetricType metric, LocalDate from, LocalDate to, ZoneId zone) {
        List<HealthReading> rows = readings
                .findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                        userId, metric,
                        from.atStartOfDay(zone).toInstant(),
                        to.plusDays(1).atStartOfDay(zone).toInstant());
        Map<LocalDate, double[]> accumulators = new TreeMap<>();
        for (HealthReading row : rows) {
            if (row.getTimestamp() == null) {
                continue;
            }
            LocalDate date = row.getTimestamp().atZone(zone).toLocalDate();
            double[] acc = accumulators.computeIfAbsent(date, key -> new double[2]);
            acc[0] += row.getValue();
            acc[1] += 1;
        }
        Map<LocalDate, Double> byDay = new TreeMap<>();
        for (Map.Entry<LocalDate, double[]> entry : accumulators.entrySet()) {
            byDay.put(entry.getKey(), entry.getValue()[0] / entry.getValue()[1]);
        }
        return byDay;
    }

    // ── helpers ────────────────────────────────────────────────────────────

    private static Map<LocalDate, DailyActivity> index(List<DailyActivity> rows) {
        Map<LocalDate, DailyActivity> byDate = new LinkedHashMap<>();
        for (DailyActivity row : rows) {
            if (row.getDate() != null) {
                byDate.put(row.getDate(), row);
            }
        }
        return byDate;
    }

    private static Double mean(java.util.Collection<Double> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        double sum = 0;
        for (Double value : values) {
            if (value == null) {
                continue;
            }
            sum += value;
        }
        return round(sum / values.size());
    }

    private static double round(double value) {
        return Math.round(value * 100d) / 100d;
    }

    private static ZoneId zone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }
}
