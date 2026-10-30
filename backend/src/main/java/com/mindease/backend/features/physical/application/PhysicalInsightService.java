package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import org.springframework.stereotype.Service;

import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.features.checkin.domain.DailyCheckin;
import com.mindease.backend.features.checkin.domain.DailyCheckinRepository;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.HealthMetricType;
import com.mindease.backend.features.physical.domain.HealthReading;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.WellnessGoal;
import com.mindease.backend.features.physical.domain.WellnessGoalRepository;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Assembles the authorised, aggregated Mind–Body context, runs the deterministic
 * pattern engine, and optionally asks the AI service for supportive wording.
 *
 * <p>Existing mental-wellness flows are untouched: this is a read-only consumer
 * of check-in and physical records, and no failure here can block the dashboard
 * or health-data sync.</p>
 */
@Service
public class PhysicalInsightService {

    static final int WINDOW_DAYS = 14;
    static final int MAX_RECOMMENDATIONS = 4;

    private final MindBodyPatternEngine engine;
    private final PhysicalInsightAiClient aiClient;
    private final DailyActivityRepository dailyActivity;
    private final SleepSessionRepository sleepSessions;
    private final DailyCheckinRepository checkins;
    private final MoodEntryRepository moods;
    private final HealthReadingRepository readings;
    private final WellnessGoalRepository goals;
    private final HydrationService hydration;

    public PhysicalInsightService(MindBodyPatternEngine engine,
                                  PhysicalInsightAiClient aiClient,
                                  DailyActivityRepository dailyActivity,
                                  SleepSessionRepository sleepSessions,
                                  DailyCheckinRepository checkins,
                                  MoodEntryRepository moods,
                                  HealthReadingRepository readings,
                                  WellnessGoalRepository goals,
                                  HydrationService hydration) {
        this.engine = engine;
        this.aiClient = aiClient;
        this.dailyActivity = dailyActivity;
        this.sleepSessions = sleepSessions;
        this.checkins = checkins;
        this.moods = moods;
        this.readings = readings;
        this.goals = goals;
        this.hydration = hydration;
    }

    public InsightDtos.InsightsResponse insights(String userId) {
        return buildInsights(userId, true);
    }

    /**
     * Deterministic variant used by the combined insight.
     *
     * <p>The combined endpoint already performs its own AI call, so asking the
     * AI service for physical wording as well would add a second external
     * round-trip on a cold cache. Patterns and recommendations are identical;
     * only the optional wording call is skipped.</p>
     */
    public InsightDtos.InsightsResponse insightsWithoutAi(String userId) {
        return buildInsights(userId, false);
    }

    private InsightDtos.InsightsResponse buildInsights(String userId, boolean includeAiWording) {
        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        LocalDate from = today.minusDays(WINDOW_DAYS - 1L);
        Instant fromInstant = from.atStartOfDay(zone).toInstant();
        Instant toInstant = today.plusDays(1).atStartOfDay(zone).toInstant();

        List<DailyActivity> activity = dailyActivity
                .findByUserIdAndDateBetweenOrderByDateDesc(userId, from, today);
        // Sleep is attributed to the wake day (SleepSession.date), so the
        // session waking on `from` starts the evening before `from`. The
        // query reaches one day back and the wake-day filter below bounds
        // the window; otherwise the window's first night was invisible.
        List<SleepSession> sleep = sleepSessions
                .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                        userId, from.minusDays(1).atStartOfDay(zone).toInstant(),
                        toInstant).stream()
                .filter(row -> row.getDate() != null
                        && !row.getDate().isBefore(from)
                        && !row.getDate().isAfter(today))
                .toList();
        List<DailyCheckin> checkinRows = checkins
                .findByUserIdAndDateBetweenOrderByDateAsc(userId, from, today);
        // The app records mood through /moods, while Mind–Body patterns read
        // DailyCheckin rows. Merge the user's real mood entries by local day so
        // co-occurrence patterns can actually fire from app usage. A stored
        // check-in always wins for its day; only days without one are
        // synthesized.
        List<MoodEntry> moodRows = moods
                .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(userId, fromInstant);
        checkinRows = mergeMoodEntries(userId, checkinRows, moodRows, zone, from, today);

        Map<LocalDate, Double> hydrationByDay = new TreeMap<>();
        for (LocalDate day = from; !day.isAfter(today); day = day.plusDays(1)) {
            Double total = hydration.todayTotalMl(userId, day);
            if (total != null) {
                hydrationByDay.put(day, total);
            }
        }

        Map<LocalDate, Double> restingHr = readingSeries(
                userId, HealthMetricType.RESTING_HEART_RATE, fromInstant, toInstant, zone);
        Map<LocalDate, Double> hrv = readingSeries(
                userId, HealthMetricType.HEART_RATE_VARIABILITY, fromInstant, toInstant, zone);

        WellnessGoal goal = goals.findByUserId(userId).orElse(null);
        MindBodyPatternEngine.WellnessContext context =
                new MindBodyPatternEngine.WellnessContext(
                        today,
                        WINDOW_DAYS,
                        activity,
                        sleep,
                        hydrationByDay,
                        checkinRows,
                        restingHr,
                        hrv,
                        goal == null ? null : goal.getDailyHydrationMl(),
                        goal == null ? null : goal.getDailySleepMinutes());

        MindBodyPatternEngine.Result result = engine.evaluate(context);
        List<InsightDtos.Recommendation> recommendations =
                new ArrayList<>(result.recommendations());
        List<String> limitations = new ArrayList<>(result.limitations());
        boolean aiEnhanced = false;

        if (!includeAiWording) {
            limitations.add("Rule-based physical context; AI wording is requested "
                    + "by the combined insight endpoint instead.");
        } else {
            PhysicalInsightAiClient.AiResult ai = aiClient.suggest(context, result);
            if (ai.available()) {
            aiEnhanced = true;
            Map<String, InsightDtos.Recommendation> unique = new LinkedHashMap<>();
            for (InsightDtos.Recommendation recommendation : recommendations) {
                unique.putIfAbsent(recommendation.id(), recommendation);
            }
            for (InsightDtos.Recommendation recommendation : ai.recommendations()) {
                unique.putIfAbsent(recommendation.id(), recommendation);
            }
            recommendations = unique.values().stream().limit(MAX_RECOMMENDATIONS).toList();
                if (ai.note() != null) {
                    limitations.add(ai.note());
                }
            } else if (result.sufficientData()) {
                limitations.add("Personalised phrasing was unavailable; rule-based guidance is shown.");
            }
        }
        limitations.add("Weight is intentionally excluded from pattern inference to avoid "
                + "unsupported body-related conclusions.");

        return new InsightDtos.InsightsResponse(
                Instant.now(),
                WINDOW_DAYS,
                result.sufficientData(),
                result.insights(),
                recommendations,
                aiEnhanced,
                result.coverage(),
                limitations,
                MindBodyPatternEngine.DISCLAIMER);
    }

    /**
     * Merges canonical mood entries into the check-in series used by the
     * pattern engine. The engine works on a 1-5 mood scale; the canonical mood
     * ids map 1-6, so the six-point value is projected onto the five-point
     * scale. A real DailyCheckin row (including its sleep/energy/stress
     * answers) is never replaced - only a null mood on an existing day is
     * filled in, and mood-only rows are synthesized for days with no check-in.
     */
    private List<DailyCheckin> mergeMoodEntries(String userId,
                                                List<DailyCheckin> stored,
                                                List<MoodEntry> moodRows,
                                                ZoneId zone,
                                                LocalDate from,
                                                LocalDate today) {
        if (moodRows == null || moodRows.isEmpty()) {
            return stored;
        }
        // Rows are newest-first; keep the latest entry per local day.
        Map<LocalDate, MoodEntry> latestByDay = new LinkedHashMap<>();
        for (MoodEntry entry : moodRows) {
            if (entry == null || entry.getRecordedAt() == null || entry.getMood() == null) {
                continue;
            }
            LocalDate day = entry.getRecordedAt().atZone(zone).toLocalDate();
            if (day.isBefore(from) || day.isAfter(today)) {
                continue;
            }
            latestByDay.putIfAbsent(day, entry);
        }
        if (latestByDay.isEmpty()) {
            return stored;
        }

        List<DailyCheckin> merged = new ArrayList<>(stored);
        Set<LocalDate> storedDays = new HashSet<>();
        for (DailyCheckin row : merged) {
            if (row.getDate() == null) {
                continue;
            }
            storedDays.add(row.getDate());
            if (row.getMood() == null) {
                MoodEntry entry = latestByDay.get(row.getDate());
                if (entry != null) {
                    row.setMood(moodToCheckinScale(entry.getMood()));
                }
            }
        }
        for (Map.Entry<LocalDate, MoodEntry> entry : latestByDay.entrySet()) {
            if (storedDays.contains(entry.getKey())) {
                continue;
            }
            MoodEntry mood = entry.getValue();
            DailyCheckin synthesized = new DailyCheckin(
                    userId,
                    entry.getKey(),
                    moodToCheckinScale(mood.getMood()),
                    null,
                    null,
                    null,
                    List.of());
            synthesized.setCreatedAt(mood.getCreatedAt());
            synthesized.setUpdatedAt(mood.getUpdatedAt());
            merged.add(synthesized);
        }
        merged.sort((a, b) -> {
            if (a.getDate() == null) {
                return b.getDate() == null ? 0 : -1;
            }
            return b.getDate() == null ? 1 : a.getDate().compareTo(b.getDate());
        });
        return merged;
    }

    /**
     * Projects the canonical 1-6 mood value onto the check-in 1-5 scale:
     * very_happy=5, happy≈4.2, calm≈3.4, okay≈2.6, low≈1.8, stressed=1.
     * "Okay" therefore stays above the engine's low-mood threshold (2.5)
     * while "low" and "stressed" remain actionable.
     */
    static int moodToCheckinScale(String mood) {
        if (mood == null) {
            return 3;
        }
        int canonical = switch (mood) {
            case "very_happy" -> 6;
            case "happy" -> 5;
            case "calm" -> 4;
            case "okay" -> 3;
            case "low" -> 2;
            case "stressed" -> 1;
            default -> 3;
        };
        return Math.max(1, Math.min(5,
                (int) Math.round(1 + (canonical - 1) * 4.0 / 5.0)));
    }

    private Map<LocalDate, Double> readingSeries(
            String userId, HealthMetricType metric, Instant from, Instant to, ZoneId zone) {
        List<HealthReading> rows = readings
                .findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                        userId, metric, from, to);
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

    private static ZoneId zone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }
}
