package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.HealthMetricType;
import com.mindease.backend.features.physical.domain.HealthReading;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSession;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.SyncSession;
import com.mindease.backend.features.physical.domain.SyncSessionRepository;
import com.mindease.backend.features.physical.dto.PhysicalWellnessAnalysisDto;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.wellness.application.WellnessAnalysisPipeline;
import com.mindease.backend.wellness.domain.WellnessAnalysisRecord;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

@Service
public class PhysicalWellnessAnalysisService {

    private static final String SCHEMA_VERSION = "1.0";
    private static final String SOURCE = "wellness-physical-analysis";
    private static final int WINDOW_DAYS = 14;

    private final DailyActivityRepository dailyActivity;
    private final HealthReadingRepository healthReadings;
    private final SleepSessionRepository sleepSessions;
    private final SyncSessionRepository syncSessions;
    private final WellnessAnalysisPipeline pipeline;
    private final WellnessGoalService wellnessGoalService;

    @org.springframework.beans.factory.annotation.Autowired
    public PhysicalWellnessAnalysisService(DailyActivityRepository dailyActivity,
                                          HealthReadingRepository healthReadings,
                                          SleepSessionRepository sleepSessions,
                                          SyncSessionRepository syncSessions,
                                          WellnessAnalysisPipeline pipeline,
                                          WellnessGoalService wellnessGoalService) {
        this.dailyActivity = dailyActivity;
        this.healthReadings = healthReadings;
        this.sleepSessions = sleepSessions;
        this.syncSessions = syncSessions;
        this.pipeline = pipeline;
        this.wellnessGoalService = wellnessGoalService;
    }

    public PhysicalWellnessAnalysisService(DailyActivityRepository dailyActivity,
                                          HealthReadingRepository healthReadings,
                                          SleepSessionRepository sleepSessions,
                                          SyncSessionRepository syncSessions,
                                          WellnessAnalysisPipeline pipeline) {
        this(dailyActivity, healthReadings, sleepSessions, syncSessions, pipeline, null);
    }

    public PhysicalWellnessAnalysisDto analyze(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new ApiException(ErrorCode.UNAUTHORIZED, "Authentication required");
        }

        LocalDate today = LocalDate.now(ZoneId.systemDefault());
        LocalDate from = today.minusDays(WINDOW_DAYS - 1);
        List<DailyActivity> activities = dailyActivity.findByUserIdAndDateBetweenOrderByDateDesc(
                userId, from, today);

        Instant fromInstant = from.atStartOfDay(ZoneId.systemDefault()).toInstant();
        Instant toInstant = today.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant();
        List<HealthReading> hrReadings = healthReadings.findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                userId, HealthMetricType.HEART_RATE, fromInstant, toInstant);
        List<HealthReading> spo2Readings = healthReadings.findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                userId, HealthMetricType.SPO2, fromInstant, toInstant);
        List<HealthReading> hrvReadings = healthReadings.findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                userId, HealthMetricType.HEART_RATE_VARIABILITY, fromInstant, toInstant);

        List<SleepSession> sleeps = sleepSessions.findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(
                userId, fromInstant.minus(1, java.time.temporal.ChronoUnit.DAYS), toInstant);

        List<SyncSession> syncs = syncSessions.findTop20ByUserIdOrderByStartedAtDesc(userId).stream().limit(10).toList();

        boolean hasActivityData = activities != null && !activities.isEmpty();
        boolean hasSleepData = sleeps != null && !sleeps.isEmpty();
        boolean hasHeartRateData = hrReadings != null && !hrReadings.isEmpty();
        boolean hasSpo2 = spo2Readings != null && !spo2Readings.isEmpty();
        boolean hasHrv = hrvReadings != null && !hrvReadings.isEmpty();
        boolean hasWearableData = hasActivityData || hasSleepData || hasHeartRateData || hasSpo2 || hasHrv;
        boolean hasRecentSync = syncs != null && !syncs.isEmpty();

        if (!hasWearableData && !hasRecentSync) {
            return PhysicalWellnessAnalysisDto.unavailable(
                    "No recent wearable data found. Sync your device or connect a watch to analyze physical wellness.");
        }

        double stepsSum = 0, distSum = 0, calSum = 0, actSum = 0;
        int stepCount = 0;
        for (DailyActivity a : activities) {
            if (a.getSteps() != null) {
                stepsSum += a.getSteps();
                stepCount++;
            }
            if (a.getDistanceMeters() != null) {
                distSum += a.getDistanceMeters();
            }
            if (a.getCaloriesKcal() != null) {
                calSum += a.getCaloriesKcal();
            }
            if (a.getActiveMinutes() != null) {
                actSum += a.getActiveMinutes();
            }
        }
        Integer stepsAvg = stepCount > 0 ? (int) Math.round(stepsSum / stepCount) : null;
        Double distAvg = activities != null && !activities.isEmpty() && distSum > 0
                ? Math.round((distSum / 1000.0 / Math.min(activities.size(), WINDOW_DAYS)) * 100.0) / 100.0
                : null;
        Integer calAvg = activities != null && !activities.isEmpty() && calSum > 0
                ? (int) Math.round(calSum / Math.min(activities.size(), WINDOW_DAYS))
                : null;
        Integer actAvg = activities != null && !activities.isEmpty() && actSum > 0
                ? (int) Math.round(actSum / Math.min(activities.size(), WINDOW_DAYS))
                : null;

        long sleepMinSum = 0;
        int sleepCount = 0;
        for (SleepSession s : sleeps) {
            if (s.getDurationMillis() != null && s.getDurationMillis() > 0) {
                sleepMinSum += s.getDurationMillis() / 60000L;
                sleepCount++;
            } else if (s.getStartTime() != null && s.getEndTime() != null) {
                sleepMinSum += ChronoUnit.MINUTES.between(s.getStartTime(), s.getEndTime());
                sleepCount++;
            }
        }
        Integer sleepHrsAvg = sleepCount > 0 ? (int) (sleepMinSum / sleepCount / 60) : null;
        Integer sleepMinsAvg = sleepCount > 0 ? (int) ((sleepMinSum / sleepCount) % 60) : null;

        double hrSum = 0;
        int hrCount = 0;
        for (HealthReading r : hrReadings) {
            if (r.getValue() != 0) {
                hrSum += r.getValue();
                hrCount++;
            }
        }
        Double hrAvg = hrCount > 0 ? Math.round((hrSum / hrCount) * 10.0) / 10.0 : null;

        double spo2Sum = 0;
        int spo2Count = 0;
        for (HealthReading r : spo2Readings) {
            if (r.getValue() != 0) {
                spo2Sum += r.getValue();
                spo2Count++;
            }
        }
        Double spo2Avg = spo2Count > 0 ? Math.round((spo2Sum / spo2Count) * 10.0) / 10.0 : null;

        double hrvSum = 0;
        int hrvCount = 0;
        for (HealthReading r : hrvReadings) {
            if (r.getValue() != 0) {
                hrvSum += r.getValue();
                hrvCount++;
            }
        }
        Double hrvAvg = hrvCount > 0 ? Math.round((hrvSum / hrvCount) * 10.0) / 10.0 : null;

        PhysicalWellnessAnalysisDto.Metrics metrics = new PhysicalWellnessAnalysisDto.Metrics(
                stepsAvg, distAvg, calAvg, actAvg, sleepHrsAvg, sleepMinsAvg, hrAvg, spo2Avg, hrvAvg, null);

        List<String> patterns = buildPatterns(stepsAvg, sleepHrsAvg, hrAvg, actAvg);
        List<String> recommendations = buildRecommendations(stepsAvg, sleepHrsAvg, hrAvg);
        List<PhysicalWellnessAnalysisDto.GoalTargetSuggestion> goalSuggestions =
                buildGoalSuggestions(stepsAvg, sleepHrsAvg, actAvg);

        if (wellnessGoalService != null && !goalSuggestions.isEmpty()) {
            try {
                List<WellnessGoalDtos.AiRecommendation> aiRecs = goalSuggestions.stream()
                        .map(g -> new WellnessGoalDtos.AiRecommendation(g.metric(), g.value(), g.rationale()))
                        .toList();
                wellnessGoalService.applyAiRecommendations(userId, aiRecs);
            } catch (Exception e) {
                // Non-blocking: analysis completes even if goal update encounters an issue
            }
        }

        Set<String> inputRefs = new HashSet<>();
        if (hasActivityData) {
            inputRefs.add("daily_activity:" + activities.size());
        }
        if (hasSleepData) {
            inputRefs.add("sleep_sessions:" + sleeps.size());
        }
        if (hasHeartRateData) {
            inputRefs.add("heart_rate:" + hrReadings.size());
        }
        if (hasSpo2) {
            inputRefs.add("spo2:" + spo2Readings.size());
        }
        if (hasHrv) {
            inputRefs.add("hrv:" + hrvReadings.size());
        }
        if (hasRecentSync && syncs.get(0).getId() != null) {
            inputRefs.add("sync:" + syncs.get(0).getId());
        }

        Instant latestReadingAt = null;
        if (hasHeartRateData && !hrReadings.isEmpty()) {
            latestReadingAt = hrReadings.get(0).getTimestamp();
        }
        if (hasActivityData && !activities.isEmpty() && activities.get(0).getUpdatedAt() != null) {
            if (latestReadingAt == null || activities.get(0).getUpdatedAt().isAfter(latestReadingAt)) {
                latestReadingAt = activities.get(0).getUpdatedAt();
            }
        }
        Instant latestSyncAt = syncs != null && !syncs.isEmpty() ? syncs.get(0).getStartedAt() : null;

        PhysicalWellnessAnalysisDto.InputSummary inputSummary = new PhysicalWellnessAnalysisDto.InputSummary(
                hasWearableData,
                hasRecentSync,
                hasActivityData,
                hasSleepData,
                hasHeartRateData,
                Math.min(activities == null ? 0 : activities.size(), WINDOW_DAYS),
                Math.min(sleeps == null ? 0 : sleeps.size(), WINDOW_DAYS),
                latestReadingAt,
                latestSyncAt);

        PhysicalWellnessAnalysisDto.Provenance provenance = new PhysicalWellnessAnalysisDto.Provenance(
                SOURCE,
                SCHEMA_VERSION,
                new ArrayList<>(inputRefs),
                Instant.now());

        String status = (stepsAvg != null && stepsAvg >= 7000 && sleepHrsAvg != null && sleepHrsAvg >= 7)
                ? "GOOD" : (hasActivityData || hasSleepData) ? "FAIR" : "INSUFFICIENT_DATA";

        // Only aggregates the screen already shows are compared or sent on.
        List<WellnessMetricDto> comparisonMetrics = new ArrayList<>();
        if (stepsAvg != null) {
            comparisonMetrics.add(new WellnessMetricDto("steps_avg", "Daily steps", stepsAvg, "steps"));
        }
        if (sleepHrsAvg != null) {
            comparisonMetrics.add(new WellnessMetricDto("sleep_hours_avg", "Sleep duration", sleepHrsAvg, "h"));
        }
        if (actAvg != null) {
            comparisonMetrics.add(new WellnessMetricDto("active_minutes_avg", "Active minutes", actAvg, "min"));
        }
        if (hrAvg != null) {
            comparisonMetrics.add(new WellnessMetricDto("resting_hr_avg", "Average heart rate", hrAvg, "bpm"));
        }
        if (hrvAvg != null) {
            comparisonMetrics.add(new WellnessMetricDto("hrv_avg", "HRV", hrvAvg, "ms"));
        }
        if (spo2Avg != null) {
            comparisonMetrics.add(new WellnessMetricDto("spo2_avg", "Blood oxygen", spo2Avg, "%"));
        }
        comparisonMetrics.add(new WellnessMetricDto("activity_days", "Days with activity",
                inputSummary.daysOfActivity() == null ? 0 : inputSummary.daysOfActivity(), "days"));
        comparisonMetrics.add(new WellnessMetricDto("sleep_days", "Nights with sleep data",
                inputSummary.daysOfSleep() == null ? 0 : inputSummary.daysOfSleep(), "nights"));

        WellnessAnalysisPipeline.Outcome outcome = pipeline.run(
                userId,
                WellnessAnalysisRecord.TYPE_PHYSICAL,
                comparisonMetrics,
                patterns,
                String.join(" ", patterns),
                recommendations,
                stepsAvg,
                status,
                provenance.inputReferences());

        return new PhysicalWellnessAnalysisDto(
                UUID.randomUUID().toString(),
                "PHYSICAL",
                Instant.now(),
                true,
                status,
                metrics,
                patterns,
                outcome.recommendations(),
                outcome.generatedBy(),
                false,
                null,
                inputSummary,
                provenance,
                outcome.advice(),
                outcome.focusAreas(),
                outcome.nextActions(),
                outcome.comparison(),
                outcome.narrative(),
                goalSuggestions);
    }

    /**
     * Targets are only suggested for metrics the user actually has data for,
     * and only when today's average is below a sustainable target. This keeps
     * AI suggestions grounded instead of inventing goals for untracked data.
     */
    private List<PhysicalWellnessAnalysisDto.GoalTargetSuggestion> buildGoalSuggestions(
            Integer stepsAvg, Integer sleepHrsAvg, Integer actAvg) {
        List<PhysicalWellnessAnalysisDto.GoalTargetSuggestion> suggestions = new ArrayList<>();
        if (stepsAvg != null && stepsAvg < 10_000) {
            int value = Math.min(10_000, Math.max(7_000, stepsAvg + 1_000));
            value = (int) (Math.ceil(value / 500.0) * 500);
            suggestions.add(new PhysicalWellnessAnalysisDto.GoalTargetSuggestion(
                    "dailySteps", value, "steps",
                    "Your recent average is " + stepsAvg + " steps/day; this target is a gradual step up."));
        }
        if (sleepHrsAvg != null && sleepHrsAvg < 7) {
            suggestions.add(new PhysicalWellnessAnalysisDto.GoalTargetSuggestion(
                    "dailySleepMinutes", 480, "min",
                    "Your recent sleep averages " + sleepHrsAvg + " h/night; 8 h is a common healthy target."));
        }
        if (actAvg != null && actAvg < 30) {
            suggestions.add(new PhysicalWellnessAnalysisDto.GoalTargetSuggestion(
                    "dailyActiveMinutes", 30, "min",
                    "Your recent activity averages " + actAvg + " active min/day; 30 min is a gentle target."));
        }
        suggestions.add(new PhysicalWellnessAnalysisDto.GoalTargetSuggestion(
                "dailyHydrationMl", 2000, "ml",
                "Maintaining 2,000 ml daily hydration supports your physical activity and recovery."));
        return suggestions;
    }

    private List<String> buildPatterns(Integer stepsAvg, Integer sleepHrsAvg, Double hrAvg, Integer actAvg) {
        List<String> patterns = new ArrayList<>();
        if (stepsAvg != null && stepsAvg >= 8000) {
            patterns.add("Good daily activity level observed over the last 14 days.");
        } else if (stepsAvg != null && stepsAvg < 5000) {
            patterns.add("Activity levels appear lower than recommended recently.");
        }
        if (sleepHrsAvg != null && sleepHrsAvg >= 7 && sleepHrsAvg <= 9) {
            patterns.add("Sleep duration is in a generally healthy range.");
        } else if (sleepHrsAvg != null && sleepHrsAvg < 7) {
            patterns.add("Recent sleep appears below the typical recommended duration.");
        }
        if (hrAvg != null && hrAvg < 100) {
            patterns.add("Resting/average heart rate appears within normal range.");
        }
        if (patterns.isEmpty()) {
            patterns.add("Physical data is being tracked; patterns will become clearer with more consistent data.");
        }
        return patterns;
    }

    private List<String> buildRecommendations(Integer stepsAvg, Integer sleepHrsAvg, Double hrAvg) {
        List<String> recs = new ArrayList<>();
        if (stepsAvg == null || stepsAvg < 7000) {
            recs.add("Aim for a short 10-15 minute walk to gradually increase daily steps.");
        }
        if (sleepHrsAvg == null || sleepHrsAvg < 7) {
            recs.add("Try to maintain a consistent sleep schedule with a relaxing wind-down routine.");
        }
        if (recs.isEmpty()) {
            recs.add("Keep maintaining your current healthy activity and sleep patterns.");
        }
        return recs;
    }
}
