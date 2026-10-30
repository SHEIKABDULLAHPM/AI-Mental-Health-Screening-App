package com.mindease.backend.features.mood.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.features.challenges.application.ChallengeActivityService;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.features.mood.dto.AnalyzeMoodRequest;
import com.mindease.backend.features.mood.dto.AnalyzeMoodResponse;
import com.mindease.backend.features.mood.dto.CreateMoodRequest;
import com.mindease.backend.features.mood.dto.MoodResponse;
import com.mindease.backend.features.mood.dto.MoodStatisticsResponse;
import com.mindease.backend.features.mood.dto.MoodTrendResponse;
import com.mindease.backend.features.mood.dto.UpdateMoodRequest;

@Service
public class MoodService {

    private static final int MAX_DAYS = 365;
    private static final int MIN_ENTRIES_FOR_TREND = 3;

    /** Tolerated clock skew when a client supplies its own recordedAt. */
    private static final java.time.Duration MAX_FUTURE_SKEW = java.time.Duration.ofMinutes(5);

    /**
     * Defensive bounds on unbounded history reads. A user would need dozens
     * of entries per day, every day, to approach these; realistic volumes are
     * unaffected while pathological memory use is capped.
     */
    private static final int MAX_WINDOW_ENTRIES = 2000;
    private static final int MAX_YEAR_ENTRIES = 5000;

    private final MoodEntryRepository repository;
    private final AuditLog audit;
    private final MoodAiClient aiClient;
    private final MoodTrendAnalyzer trendAnalyzer;
    private final MoodGuidanceEngine guidanceEngine;
    private final MoodSafetyDetector safetyDetector;
    private final MoodReflectionPrompts reflectionPrompts;
    private final PersonalizationService personalizationService;
    private final ChallengeActivityService challengeActivityService;
    private final Executor sideEffects;

    public MoodService(
            MoodEntryRepository repository,
            AuditLog audit,
            MoodAiClient aiClient,
            MoodTrendAnalyzer trendAnalyzer,
            MoodGuidanceEngine guidanceEngine,
            MoodSafetyDetector safetyDetector,
            MoodReflectionPrompts reflectionPrompts,
            PersonalizationService personalizationService,
            ChallengeActivityService challengeActivityService,
            @Qualifier("sideEffectExecutor") Executor sideEffects) {
        this.repository = repository;
        this.audit = audit;
        this.aiClient = aiClient;
        this.trendAnalyzer = trendAnalyzer;
        this.guidanceEngine = guidanceEngine;
        this.safetyDetector = safetyDetector;
        this.reflectionPrompts = reflectionPrompts;
        this.personalizationService = personalizationService;
        this.challengeActivityService = challengeActivityService;
        this.sideEffects = sideEffects;
    }

    public MoodResponse createMood(String userId, CreateMoodRequest request) {
        Instant now = Instant.now();
        if (request.recordedAt() != null
                && request.recordedAt().isAfter(now.plus(MAX_FUTURE_SKEW))) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "Mood recordedAt cannot be in the future.");
        }
        MoodEntry entry = new MoodEntry();
        entry.setUserId(userId);
        entry.setMood(request.mood());
        entry.setEmotion(request.emotion());
        entry.setNote(request.note());
        entry.setIntensity(request.intensity());
        entry.setRecordedAt(request.recordedAt() != null ? request.recordedAt() : now);
        entry.setCreatedAt(now);
        entry.setUpdatedAt(now);

        String source = request.source() != null ? request.source() : "MANUAL";
        entry.setSource(source);
        entry.setConfidence(request.confidence());
        entry.setAiSuggestedMood(request.aiSuggestedMood());

        if (request.aiObservations() != null && !request.aiObservations().isEmpty()) {
            List<MoodEntry.AiObservation> observations = request.aiObservations().stream()
                    .map(input -> {
                        MoodEntry.AiObservation obs = new MoodEntry.AiObservation();
                        obs.setSource(input.source());
                        obs.setEmotion(input.emotion());
                        obs.setConfidence(input.confidence());
                        obs.setSentiment(input.sentiment());
                        obs.setSentimentConfidence(input.sentimentConfidence());
                        obs.setSuggestedMood(input.suggestedMood());
                        obs.setModelVersion(input.modelVersion());
                        return obs;
                    })
                    .toList();
            entry.setAiObservations(observations);
            entry.setAnalysisStatus("COMPLETED");
        } else if ("MANUAL".equals(source)) {
            entry.setAnalysisStatus("NONE");
        } else {
            entry.setAnalysisStatus("COMPLETED");
        }

        MoodEntry saved = repository.save(entry);
        audit.event(userId, "mood.created", saved.getId());

        // Trigger personalization context refresh (genuinely fire-and-forget:
        // bounded executor with caller-runs fallback; callee swallows errors).
        CompletableFuture.runAsync(
                () -> personalizationService.recordFeedback(userId, "MOOD_RECORDED", saved.getId(),
                        "mood", java.util.Map.of("mood", request.mood())),
                sideEffects);

        // Advance any matching started mood challenges (fire-and-forget).
        CompletableFuture.runAsync(
                () -> challengeActivityService.onMoodRecorded(userId, saved.getId(), null),
                sideEffects);

        return MoodResponse.from(saved);
    }

    /**
     * Analyze mood via the AI service, enrich with trend/guidance/safety/reflection,
     * and return the full structured result.
     * Does NOT save - the caller decides whether to confirm and save.
     */
    @SuppressWarnings("unchecked")
    public AnalyzeMoodResponse analyzeMood(String userId, AnalyzeMoodRequest request) {
        AnalyzeMoodResponse aiResult = aiClient.analyzeMood(request);

        Instant since = Instant.now().minus(30, ChronoUnit.DAYS);
        List<MoodEntry> recentEntries = repository
                .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                        userId, since, PageRequest.of(0, MAX_WINDOW_ENTRIES));

        Map<String, Object> trendData = trendAnalyzer.analyzeTrend(recentEntries);
        AnalyzeMoodResponse.TrendResult trend = new AnalyzeMoodResponse.TrendResult(
                (String) trendData.get("direction"),
                (String) trendData.get("description"),
                trendData.get("dataPoints") != null ? (Integer) trendData.get("dataPoints") : 0);

        Map<String, Object> safetyData = safetyDetector.analyze(request.note());
        boolean safetyFlag = Boolean.TRUE.equals(safetyData.get("flag"));
        AnalyzeMoodResponse.SafetyResult safety = new AnalyzeMoodResponse.SafetyResult(
                safetyFlag,
                (String) safetyData.get("level"),
                (String) safetyData.get("message"),
                safetyFlag ? (Map<String, String>) safetyData.get("resources") : null);

        String sentiment = null;
        if (aiResult.textAnalysis() != null) {
            sentiment = aiResult.textAnalysis().sentiment();
        }

        Map<String, Object> guidanceData = guidanceEngine.generateGuidance(
                aiResult.fusedMood(),
                aiResult.fusedEmotion(),
                sentiment,
                trend.direction());
        if (safetyFlag) {
            guidanceData.put("safetyFlag", true);
            guidanceData.put("message", "Your safety is important. "
                    + "Please consider reaching out to a support resource.");
        }
        AnalyzeMoodResponse.GuidanceResult guidance = new AnalyzeMoodResponse.GuidanceResult(
                (String) guidanceData.get("message"),
                (List<Map<String, String>>) guidanceData.get("actions"),
                (Boolean) guidanceData.get("safetyFlag"));

        Map<String, String> reflectionData = reflectionPrompts.getStructuredPrompt(
                aiResult.fusedMood());
        AnalyzeMoodResponse.ReflectionResult reflection = new AnalyzeMoodResponse.ReflectionResult(
                reflectionData.get("text"),
                reflectionData.get("moodContext"),
                reflectionData.get("type"));

        return new AnalyzeMoodResponse(
                aiResult.fusedMood(),
                aiResult.aiSuggestedMood(),
                aiResult.fusedEmotion(),
                aiResult.confidence(),
                aiResult.sourcesUsed(),
                aiResult.manualMood(),
                aiResult.textAnalysis(),
                aiResult.cameraAnalysis(),
                aiResult.needsConfirmation(),
                aiResult.modelVersion(),
                trend,
                guidance,
                safety,
                reflection);
    }

    public List<MoodResponse> getMoodEntries(String userId, int page, int size) {
        Pageable pageable = PageRequest.of(page, size);
        return repository.findByUserIdOrderByRecordedAtDesc(userId, pageable)
                .stream()
                .map(MoodResponse::from)
                .toList();
    }

    public MoodResponse getMoodById(String userId, String id) {
        MoodEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "Mood entry not found or no longer available."));
        return MoodResponse.from(entry);
    }

    public List<MoodResponse> getRecentMoods(String userId, int limit) {
        Pageable pageable = PageRequest.of(0, Math.min(limit, 50));
        return repository.findByUserIdOrderByRecordedAtDesc(userId, pageable)
                .stream()
                .map(MoodResponse::from)
                .toList();
    }

    public MoodResponse updateMood(String userId, String id, UpdateMoodRequest request) {
        MoodEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "Mood entry not found or no longer available."));

        if (request.mood() != null) {
            entry.setMood(request.mood());
        }
        if (request.emotion() != null) {
            entry.setEmotion(request.emotion());
        }
        if (request.note() != null) {
            entry.setNote(request.note());
        }
        if (request.intensity() != null) {
            entry.setIntensity(request.intensity());
        }
        entry.setUpdatedAt(Instant.now());

        MoodEntry saved = repository.save(entry);
        audit.event(userId, "mood.updated", saved.getId());
        return MoodResponse.from(saved);
    }

    public void deleteMood(String userId, String id) {
        MoodEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "Mood entry not found or no longer available."));

        repository.delete(entry);
        audit.event(userId, "mood.deleted", id);
    }

    public List<MoodTrendResponse> getMoodTrends(String userId, int days) {
        int safeDays = Math.min(Math.max(days, 1), MAX_DAYS);
        Instant since = Instant.now().minus(safeDays, ChronoUnit.DAYS);
        List<MoodEntry> entries = repository
                .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                        userId, since, PageRequest.of(0, MAX_WINDOW_ENTRIES));

        Map<String, Long> moodCounts = entries.stream()
                .collect(Collectors.groupingBy(MoodEntry::getMood, Collectors.counting()));

        return moodCounts.entrySet().stream()
                .map(e -> new MoodTrendResponse(e.getKey(), e.getValue()))
                .sorted((a, b) -> Long.compare(b.count(), a.count()))
                .toList();
    }

    public Map<String, Object> getEnhancedTrends(String userId, int days) {
        int safeDays = Math.min(Math.max(days, 1), MAX_DAYS);
        Instant since = Instant.now().minus(safeDays, ChronoUnit.DAYS);
        List<MoodEntry> entries = repository
                .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                        userId, since, PageRequest.of(0, MAX_WINDOW_ENTRIES));

        Map<String, Long> moodDistribution = entries.stream()
                .collect(Collectors.groupingBy(MoodEntry::getMood, Collectors.counting()));

        Map<String, Long> emotionDistribution = new LinkedHashMap<>();
        for (MoodEntry entry : entries) {
            String emotion = entry.getEmotion();
            if (emotion != null) {
                emotionDistribution.merge(emotion, 1L, Long::sum);
            }
        }

        Map<String, Long> sourceBreakdown = entries.stream()
                .filter(e -> e.getSource() != null)
                .collect(Collectors.groupingBy(MoodEntry::getSource, Collectors.counting()));

        ZoneId utc = ZoneId.of("UTC");
        Map<LocalDate, List<MoodEntry>> byDate = entries.stream()
                .filter(e -> e.getRecordedAt() != null)
                .collect(Collectors.groupingBy(
                        e -> e.getRecordedAt().atZone(utc).toLocalDate(),
                        LinkedHashMap::new,
                        Collectors.toList()));

        List<Map<String, Object>> dailyData = new ArrayList<>();
        byDate.entrySet().stream()
                .sorted(Map.Entry.comparingByKey())
                .forEach(entry -> {
                    Map<String, Object> day = new LinkedHashMap<>();
                    day.put("date", entry.getKey().toString());
                    day.put("count", (long) entry.getValue().size());
                    day.put("moods", entry.getValue().stream().map(MoodEntry::getMood).toList());
                    day.put("avgValue", entry.getValue().stream()
                            .mapToInt(e -> moodToValue(e.getMood()))
                            .average()
                            .orElse(0.0));
                    dailyData.add(day);
                });

        Map<String, Object> trendData = trendAnalyzer.analyzeTrend(entries);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("period", safeDays);
        result.put("totalEntries", (long) entries.size());
        result.put("moodDistribution", moodDistribution);
        result.put("emotionDistribution", emotionDistribution);
        result.put("sourceBreakdown", sourceBreakdown);
        result.put("dailyData", dailyData);
        result.put("trend", trendData);
        result.put("moodTrends", moodDistribution.entrySet().stream()
                .map(e -> new MoodTrendResponse(e.getKey(), e.getValue()))
                .sorted((a, b) -> Long.compare(b.count(), a.count()))
                .toList());

        if (entries.size() < MIN_ENTRIES_FOR_TREND) {
            result.put("status", "INSUFFICIENT_DATA");
            result.put("message", "Not enough mood records to generate a meaningful trend. "
                    + "Continue logging to see your patterns.");
        } else {
            result.put("status", "OK");
        }

        return result;
    }

    public MoodStatisticsResponse getMoodStatistics(String userId) {        Instant yearAgo = Instant.now().minus(365, ChronoUnit.DAYS);
        List<MoodEntry> allEntries = repository
                .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                        userId, yearAgo, PageRequest.of(0, MAX_YEAR_ENTRIES));

        Instant weekAgo = Instant.now().minus(7, ChronoUnit.DAYS);
        long entriesThisWeek = allEntries.stream()
                .filter(e -> e.getRecordedAt() != null && e.getRecordedAt().isAfter(weekAgo))
                .count();

        Map<String, Long> moodDistribution = allEntries.stream()
                .collect(Collectors.groupingBy(MoodEntry::getMood, Collectors.counting()));

        String mostCommonMood = moodDistribution.entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .map(Map.Entry::getKey)
                .orElse("none");

        Double averageIntensity = allEntries.stream()
                .filter(e -> e.getIntensity() != null)
                .mapToInt(MoodEntry::getIntensity)
                .average()
                .orElse(0.0);

        ZoneId utc = ZoneId.of("UTC");
        LocalDate today = LocalDate.now(utc);

        List<LocalDate> entryDates = allEntries.stream()
                .filter(e -> e.getRecordedAt() != null)
                .map(e -> e.getRecordedAt().atZone(utc).toLocalDate())
                .distinct()
                .sorted((a, b) -> b.compareTo(a))
                .toList();

        int currentStreak = 0;
        LocalDate checkDate = today;
        for (LocalDate date : entryDates) {
            if (date.equals(checkDate)) {
                currentStreak++;
                checkDate = checkDate.minusDays(1);
            } else if (date.isBefore(checkDate)) {
                break;
            }
        }

        int longestStreak = 0;
        int streak = 0;
        LocalDate prevDate = null;
        for (LocalDate date : entryDates.reversed()) {
            if (prevDate != null && date.equals(prevDate.plusDays(1))) {
                streak++;
            } else {
                streak = 1;
            }
            longestStreak = Math.max(longestStreak, streak);
            prevDate = date;
        }

        return new MoodStatisticsResponse(
                allEntries.size(),
                (int) entriesThisWeek,
                currentStreak,
                longestStreak,
                mostCommonMood,
                Math.round(averageIntensity * 10.0) / 10.0,
                moodDistribution);
    }

    /**
     * Combined onboarding mood context in a single call: recent entries, the
     * authoritative enhanced trend and statistics. Reuses the exact same
     * calculations as the standalone endpoints — one HTTP round-trip instead
     * of three, no duplicated logic. Never throws for missing data; empty
     * history degrades to hasHistory=false with an "unknown" trend.
     */
    public Map<String, Object> getOnboardingMoodSummary(String userId) {
        List<MoodResponse> recent;
        Map<String, Object> trends;
        MoodStatisticsResponse stats;
        try {
            recent = getRecentMoods(userId, 5);
        } catch (Exception e) {
            recent = List.of();
        }
        try {
            trends = getEnhancedTrends(userId, 30);
        } catch (Exception e) {
            trends = new LinkedHashMap<>();
            trends.put("status", "UNAVAILABLE");
            trends.put("totalEntries", 0L);
            trends.put("trend", Map.of(
                    "direction", "unknown",
                    "description", "Mood history is currently unavailable.",
                    "dataPoints", 0));
        }
        try {
            stats = getMoodStatistics(userId);
        } catch (Exception e) {
            stats = new MoodStatisticsResponse(0, 0, 0, 0, "none", 0.0, Map.of());
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("hasHistory", !recent.isEmpty());
        result.put("recent", recent);
        result.put("trends", trends);
        result.put("statistics", Map.of(
                "totalEntries", stats.totalEntries(),
                "entriesThisWeek", stats.entriesThisWeek(),
                "currentStreak", stats.currentStreak(),
                "mostCommonMood", stats.mostCommonMood()));
        Object trendObj = trends.get("trend");
        if (trendObj instanceof Map<?, ?> trendMap) {
            result.put("trendDirection", trendMap.get("direction"));
            result.put("trendDescription", trendMap.get("description"));
        } else {
            result.put("trendDirection", "unknown");
            result.put("trendDescription", "Not enough mood records to determine a trend.");
        }
        return result;
    }

    /**
     * Lightweight mood summary for the dashboard home tab. Derived from the
     * same MoodService history + MoodTrendAnalyzer as every other surface, so
     * dashboard, onboarding and trends can never disagree.
     */
    public Map<String, Object> getDashboardMoodSummary(String userId) {
        List<MoodEntry> entries = repository
                .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                        userId, Instant.now().minus(30, ChronoUnit.DAYS),
                        PageRequest.of(0, MAX_WINDOW_ENTRIES));
        Map<String, Object> result = new LinkedHashMap<>();
        if (entries.isEmpty()) {
            result.put("hasHistory", false);
            result.put("currentMood", null);
            result.put("moodScore", null);
            result.put("trendDirection", "unknown");
            result.put("trendDescription", "No mood history yet.");
            result.put("historyCount", 0);
            return result;
        }
        // Entries are newest-first, so index 0 is the current mood.
        MoodEntry current = entries.get(0);
        Map<String, Object> trend = trendAnalyzer.analyzeTrend(entries);
        result.put("hasHistory", true);
        result.put("currentMood", current.getMood());
        result.put("moodEmotion", current.getEmotion());
        result.put("moodScore", MoodTrendAnalyzer.moodToValue(current.getMood()));
        result.put("trendDirection", trend.getOrDefault("direction", "unknown"));
        result.put("trendDescription", trend.getOrDefault("description", ""));
        result.put("historyCount", entries.size());
        return result;
    }

    static int moodToValue(String mood) {
        // Single source of truth lives in MoodTrendAnalyzer — never fork this table.
        return MoodTrendAnalyzer.moodToValue(mood);
    }
}
