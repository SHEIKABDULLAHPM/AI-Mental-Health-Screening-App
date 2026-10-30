package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.features.checkin.domain.DailyCheckin;
import com.mindease.backend.features.checkin.domain.DailyCheckinRepository;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.WellnessGoalRepository;
import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Insight orchestration must degrade gracefully: the AI service adds wording,
 * never truth. If it is down, the rule-based insights and recommendations still
 * reach the user unchanged.
 */
@ExtendWith(MockitoExtension.class)
class PhysicalInsightServiceTest {

    private static final String USER = "user-a";

    @Mock
    private MindBodyPatternEngine engine;
    @Mock
    private PhysicalInsightAiClient aiClient;
    @Mock
    private DailyActivityRepository dailyActivity;
    @Mock
    private SleepSessionRepository sleepSessions;
    @Mock
    private DailyCheckinRepository checkins;
    @Mock
    private MoodEntryRepository moods;
    @Mock
    private HealthReadingRepository readings;
    @Mock
    private WellnessGoalRepository goals;
    @Mock
    private HydrationService hydration;

    private PhysicalInsightService service;

    @BeforeEach
    void setUp() {
        UserTimeZoneHolder.set("UTC");
        service = new PhysicalInsightService(engine, aiClient, dailyActivity, sleepSessions,
                checkins, moods, readings, goals, hydration);
        lenient().when(dailyActivity
                        .findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(sleepSessions
                        .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(checkins.findByUserIdAndDateBetweenOrderByDateAsc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(moods
                        .findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(any(), any()))
                .thenReturn(List.of());
        lenient().when(readings
                        .findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                                any(), any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(goals.findByUserId(USER)).thenReturn(Optional.empty());
        lenient().when(hydration.todayTotalMl(eq(USER), any())).thenReturn(null);
    }

    private InsightDtos.DataCoverage coverage() {
        return new InsightDtos.DataCoverage(14, 10, 8, 5, 6, 4, List.of("SPO2"));
    }

    private InsightDtos.PatternInsight sleepInsight() {
        return new InsightDtos.PatternInsight(
                "sleep_below_baseline", "Sleep has been shorter", "Summary", "ATTENTION",
                "MEDIUM",
                List.of(new InsightDtos.Evidence("SLEEP", "sleep_duration", 360d, 480d,
                        "min", 14, 3, "below_baseline")),
                coverage(), MindBodyPatternEngine.DISCLAIMER);
    }

    private MindBodyPatternEngine.Result ruleResult() {
        return new MindBodyPatternEngine.Result(
                List.of(sleepInsight()),
                List.of(new InsightDtos.Recommendation("sleep_wind_down", "Wind down",
                        "Keep a routine", "SLEEP", "RULE_ENGINE")),
                coverage(), true, List.of("Activity coverage: 10/14 days."));
    }

    @Test
    void aiUnavailable_stillReturnsRuleBasedInsights() {
        when(engine.evaluate(any())).thenReturn(ruleResult());
        when(aiClient.suggest(any(), any())).thenReturn(PhysicalInsightAiClient.AiResult
                .unavailable());

        var response = service.insights(USER);

        assertThat(response.insights()).hasSize(1);
        assertThat(response.recommendations()).extracting(rec -> rec.id())
                .containsExactly("sleep_wind_down");
        assertThat(response.aiEnhanced()).isFalse();
        assertThat(response.limitations())
                .anyMatch(note -> note.contains("rule-based guidance"));
    }

    @Test
    void combinedVariantSkipsTheAiWordingCall() {
        when(engine.evaluate(any())).thenReturn(ruleResult());

        var response = service.insightsWithoutAi(USER);

        assertThat(response.aiEnhanced()).isFalse();
        assertThat(response.recommendations()).extracting(rec -> rec.id())
                .containsExactly("sleep_wind_down");
        verify(aiClient, never()).suggest(any(), any());
    }

    @Test
    void aiAvailable_mergesWithoutDuplicatingRuleEngineIds() {
        when(engine.evaluate(any())).thenReturn(ruleResult());
        when(aiClient.suggest(any(), any())).thenReturn(new PhysicalInsightAiClient.AiResult(
                true,
                List.of(
                        new InsightDtos.Recommendation("sleep_wind_down", "Wind down",
                                "Duplicate", "SLEEP", "AI_SERVICE"),
                        new InsightDtos.Recommendation("ai_walk", "Walk", "Gentle walk",
                                "ACTIVITY", "AI_SERVICE")),
                "AI note"));

        var response = service.insights(USER);

        assertThat(response.aiEnhanced()).isTrue();
        assertThat(response.recommendations()).extracting(rec -> rec.id())
                .containsExactly("sleep_wind_down", "ai_walk");
        assertThat(response.recommendations().get(0).source()).isEqualTo("RULE_ENGINE");
        assertThat(response.limitations()).contains("AI note");
    }

    @Test
    void responseCarriesBoundedRecommendationsAndHonestLimitations() {
        when(engine.evaluate(any())).thenReturn(ruleResult());
        when(aiClient.suggest(any(), any())).thenReturn(new PhysicalInsightAiClient.AiResult(
                true,
                List.of(
                        new InsightDtos.Recommendation("a1", "A", "A desc", "X", "AI_SERVICE"),
                        new InsightDtos.Recommendation("a2", "B", "B desc", "X", "AI_SERVICE"),
                        new InsightDtos.Recommendation("a3", "C", "C desc", "X", "AI_SERVICE"),
                        new InsightDtos.Recommendation("a4", "D", "D desc", "X", "AI_SERVICE"),
                        new InsightDtos.Recommendation("a5", "E", "E desc", "X", "AI_SERVICE")),
                null));

        var response = service.insights(USER);

        assertThat(response.recommendations()).hasSizeLessThanOrEqualTo(4);
        assertThat(response.limitations())
                .anyMatch(note -> note.contains("Weight is intentionally excluded"));
        assertThat(response.disclaimer()).isEqualTo(MindBodyPatternEngine.DISCLAIMER);
        assertThat(response.generatedAt()).isNotNull();
        assertThat(response.windowDays()).isEqualTo(PhysicalInsightService.WINDOW_DAYS);
    }

    @Test
    void insufficientData_isReportedAsSuchAndSkipsAi() {
        var insufficient = new MindBodyPatternEngine.Result(
                List.of(new InsightDtos.PatternInsight(
                        "insufficient_recent_data", "Not enough data", "No conclusions",
                        "INFO", "LOW", List.of(), coverage(),
                        MindBodyPatternEngine.DISCLAIMER)),
                List.of(), coverage(), false, List.of("Data is stale or missing."));
        when(engine.evaluate(any())).thenReturn(insufficient);
        when(aiClient.suggest(any(), any())).thenReturn(PhysicalInsightAiClient.AiResult
                .unavailable());

        var response = service.insights(USER);

        assertThat(response.sufficientData()).isFalse();
        assertThat(response.insights().get(0).id()).isEqualTo("insufficient_recent_data");
        assertThat(response.recommendations()).isEmpty();
        // No "AI unavailable" noise when there was nothing to enhance.
        assertThat(response.limitations())
                .noneMatch(note -> note.contains("rule-based guidance"));
    }

    @Test
    void checkinsAreReadOnlyInputs() {
        when(engine.evaluate(any())).thenReturn(ruleResult());
        when(aiClient.suggest(any(), any())).thenReturn(PhysicalInsightAiClient.AiResult
                .unavailable());

        service.insights(USER);

        // Only the read method is ever called: the insight layer cannot mutate
        // the mental-wellness record.
        org.mockito.Mockito.verify(checkins)
                .findByUserIdAndDateBetweenOrderByDateAsc(eq(USER), any(), any());
        org.mockito.Mockito.verifyNoMoreInteractions(checkins);
    }

    @Test
    void appMoodEntriesAreMergedIntoPatternContext() {
        java.time.Instant now = java.time.Instant.now();
        MoodEntry entry = new MoodEntry();
        entry.setId("mood-1");
        entry.setUserId(USER);
        entry.setMood("stressed");
        entry.setRecordedAt(now);
        when(moods.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(eq(USER), any()))
                .thenReturn(List.of(entry));
        when(engine.evaluate(any())).thenReturn(ruleResult());
        when(aiClient.suggest(any(), any()))
                .thenReturn(PhysicalInsightAiClient.AiResult.unavailable());

        service.insights(USER);

        org.mockito.ArgumentCaptor<MindBodyPatternEngine.WellnessContext> captor =
                org.mockito.ArgumentCaptor.forClass(MindBodyPatternEngine.WellnessContext.class);
        org.mockito.Mockito.verify(engine).evaluate(captor.capture());
        assertThat(captor.getValue().checkins())
                .anyMatch(row -> row.getMood() != null && row.getMood() == 1);
    }

    @Test
    void storedCheckinMoodWinsOverMoodEntryForTheSameDay() {
        java.time.Instant now = java.time.Instant.now();
        java.time.LocalDate day = java.time.LocalDate.now(java.time.ZoneOffset.UTC);
        DailyCheckin stored = new DailyCheckin(USER, day, 5, 4, 4, 2, List.of());
        when(checkins.findByUserIdAndDateBetweenOrderByDateAsc(eq(USER), any(), any()))
                .thenReturn(List.of(stored));
        MoodEntry entry = new MoodEntry();
        entry.setUserId(USER);
        entry.setMood("stressed");
        entry.setRecordedAt(now);
        when(moods.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(eq(USER), any()))
                .thenReturn(List.of(entry));
        when(engine.evaluate(any())).thenReturn(ruleResult());
        when(aiClient.suggest(any(), any()))
                .thenReturn(PhysicalInsightAiClient.AiResult.unavailable());

        service.insights(USER);

        org.mockito.ArgumentCaptor<MindBodyPatternEngine.WellnessContext> captor =
                org.mockito.ArgumentCaptor.forClass(MindBodyPatternEngine.WellnessContext.class);
        org.mockito.Mockito.verify(engine).evaluate(captor.capture());
        assertThat(captor.getValue().checkins()).hasSize(1);
        assertThat(captor.getValue().checkins().get(0).getMood()).isEqualTo(5);
    }
}
