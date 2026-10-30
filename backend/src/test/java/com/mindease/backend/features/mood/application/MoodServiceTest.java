package com.mindease.backend.features.mood.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;

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

@ExtendWith(MockitoExtension.class)
class MoodServiceTest {

    @Mock
    private MoodEntryRepository repository;

    @Mock
    private AuditLog audit;

    @Mock
    private MoodAiClient aiClient;

    @Mock
    private MoodTrendAnalyzer trendAnalyzer;

    @Mock
    private MoodGuidanceEngine guidanceEngine;

    @Mock
    private MoodSafetyDetector safetyDetector;

    @Mock
    private MoodReflectionPrompts reflectionPrompts;

    @Mock
    private PersonalizationService personalizationService;

    @Mock
    private ChallengeActivityService challengeActivityService;

    private MoodService service;

    private static final String USER_ID = "user-1";
    private static final String MOOD_ID = "mood-1";
    private static final String OTHER_USER_ID = "other-user";

    @BeforeEach
    void setUp() {
        service = new MoodService(repository, audit, aiClient,
                trendAnalyzer, guidanceEngine, safetyDetector, reflectionPrompts,
                personalizationService, challengeActivityService,
                // Direct executor: side effects run inline so existing
                // assertions keep their exact synchronous semantics.
                Runnable::run);
    }

    // --------------------------------------------------------------- createMood

    @Test
    void createMoodSuccessfully() {
        CreateMoodRequest request = new CreateMoodRequest("happy", "joy", "Great day today!",
                null, "MANUAL", null, 1.0, null, 7);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.mood()).isEqualTo("happy");
        assertThat(response.emotion()).isEqualTo("joy");
        assertThat(response.note()).isEqualTo("Great day today!");
        assertThat(response.id()).isEqualTo(MOOD_ID);
        assertThat(response.source()).isEqualTo("MANUAL");
        assertThat(response.analysisStatus()).isEqualTo("NONE");
        assertThat(response.intensity()).isEqualTo(7);
        verify(repository).save(any(MoodEntry.class));
        verify(audit).event(eq(USER_ID), eq("mood.created"), eq(MOOD_ID));
    }

    @Test
    void createMoodUsesProvidedRecordedAt() {
        Instant recordedAt = Instant.now().minus(1, ChronoUnit.HOURS);
        CreateMoodRequest request = new CreateMoodRequest("calm", "peace", null,
                recordedAt, "MANUAL", null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.recordedAt()).isEqualTo(recordedAt);
    }

    @Test
    void createMoodRejectsFutureRecordedAtBeyondClockSkew() {
        CreateMoodRequest request = new CreateMoodRequest("calm", "peace", null,
                Instant.now().plus(2, ChronoUnit.HOURS), "MANUAL", null, null, null, null);

        assertThatThrownBy(() -> service.createMood(USER_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.VALIDATION_FAILED);
        verify(repository, never()).save(any());
    }

    @Test
    void createMoodAcceptsSmallClockSkew() {
        Instant recordedAt = Instant.now().plus(2, ChronoUnit.MINUTES);
        CreateMoodRequest request = new CreateMoodRequest("calm", "peace", null,
                recordedAt, "MANUAL", null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.recordedAt()).isEqualTo(recordedAt);
    }

    @Test
    void createMoodWithAiObservations() {
        CreateMoodRequest request = new CreateMoodRequest("happy", "joy", "Good",
                null, "MULTIMODAL",
                List.of(new CreateMoodRequest.AiObservationInput(
                        "TEXT", "joy", 0.9, "positive", 0.85, "happy", "v1.0")),
                0.88, "happy", null);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.source()).isEqualTo("MULTIMODAL");
        assertThat(response.confidence()).isEqualTo(0.88);
        assertThat(response.aiSuggestedMood()).isEqualTo("happy");
        assertThat(response.aiObservations()).hasSize(1);
        assertThat(response.aiObservations().get(0).emotion()).isEqualTo("joy");
        assertThat(response.analysisStatus()).isEqualTo("COMPLETED");
    }

    @Test
    void aiSuggestionIsStoredSeparatelyFromTheUsersOwnMood() {
        // Fusion keeps the user's manual selection authoritative, so the mood is
        // "calm" while the AI independently read "okay". The AI signal must
        // survive as its own field instead of being overwritten by, or
        // collapsed into, the user's choice.
        CreateMoodRequest request = new CreateMoodRequest("calm", "grateful", "Rough day",
                null, "MULTIMODAL",
                List.of(new CreateMoodRequest.AiObservationInput(
                        "TEXT", "anxiety", 0.8, "negative", 0.7, "stressed", "v1.0")),
                0.84, "okay", null);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.mood()).isEqualTo("calm");
        assertThat(response.aiSuggestedMood()).isEqualTo("okay");
        assertThat(response.aiSuggestedMood()).isNotEqualTo(response.mood());
    }

    @Test
    void createMoodDefaultSourceIsManual() {
        CreateMoodRequest request = new CreateMoodRequest("calm", null, null,
                null, null, null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.source()).isEqualTo("MANUAL");
    }

    @Test
    void createMoodWithAiObservationsConfidenceValidation() {
        assertThatThrownBy(() -> new CreateMoodRequest.AiObservationInput(
                "TEXT", "joy", -0.1, "positive", 0.85, "happy", "v1.0"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("confidence");

        assertThatThrownBy(() -> new CreateMoodRequest.AiObservationInput(
                "TEXT", "joy", 1.1, "positive", 0.85, "happy", "v1.0"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("confidence");

        assertThatThrownBy(() -> new CreateMoodRequest.AiObservationInput(
                "TEXT", "joy", 0.9, "positive", -0.1, "happy", "v1.0"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("confidence");

        CreateMoodRequest.AiObservationInput valid = new CreateMoodRequest.AiObservationInput(
                "TEXT", "joy", 0.9, "positive", 0.85, "happy", "v1.0");
        assertThat(valid).isNotNull();
    }

    // --------------------------------------------------------------- analyzeMood

    @Test
    void analyzeMoodDelegatesToAiClient() {
        AnalyzeMoodRequest request = new AnalyzeMoodRequest("happy", "joy", "Great", null);
        AnalyzeMoodResponse expected = new AnalyzeMoodResponse(
                "happy", null, "joy", 0.9, List.of("TEXT", "MANUAL"),
                "happy",
                new AnalyzeMoodResponse.TextAnalysisResult(
                        "TEXT", "joy", 0.9, "positive", 0.85, "happy", "v1.0"),
                null, false, "v1.0",
                null, null, null, null);
        when(aiClient.analyzeMood(request)).thenReturn(expected);
        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(any(), any(), any(org.springframework.data.domain.Pageable.class)))
                .thenReturn(List.of());
        when(trendAnalyzer.analyzeTrend(any())).thenReturn(
                Map.of("direction", "unknown", "description", "Not enough data", "dataPoints", 0));
        // Note: Map.of forbids null values; omitted "message" key yields null via get()
        when(safetyDetector.analyze(any())).thenReturn(Map.of("flag", false, "level", "none"));
        when(guidanceEngine.generateGuidance(any(), any(), any(), any())).thenReturn(
                Map.of("message", "Test", "actions", List.of(), "safetyFlag", false));
        when(reflectionPrompts.getStructuredPrompt(any())).thenReturn(
                Map.of("text", "Test?", "moodContext", "happy", "type", "reflection"));

        AnalyzeMoodResponse response = service.analyzeMood(USER_ID, request);

        assertThat(response.fusedMood()).isEqualTo("happy");
        assertThat(response.confidence()).isEqualTo(0.9);
        verify(aiClient).analyzeMood(request);
    }

    @Test
    void analyzeMoodFallsBackOnAiFailure() {
        AnalyzeMoodRequest request = new AnalyzeMoodRequest("happy", "joy", "Great", null);
        // MoodAiClient handles AI failures internally and returns a manual-only fallback
        AnalyzeMoodResponse fallback = new AnalyzeMoodResponse(
                "happy", null, "neutral", 0.0, List.of("MANUAL"), "happy",
                null, null, false, "unavailable",
                null, null, null, null);
        when(aiClient.analyzeMood(request)).thenReturn(fallback);
        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(any(), any(), any(org.springframework.data.domain.Pageable.class)))
                .thenReturn(List.of());
        when(trendAnalyzer.analyzeTrend(any())).thenReturn(
                Map.of("direction", "unknown", "description", "Not enough data", "dataPoints", 0));
        // Note: Map.of forbids null values; omitted "message" key yields null via get()
        when(safetyDetector.analyze(any())).thenReturn(Map.of("flag", false, "level", "none"));
        when(guidanceEngine.generateGuidance(any(), any(), any(), any())).thenReturn(
                Map.of("message", "Test", "actions", List.of(), "safetyFlag", false));
        when(reflectionPrompts.getStructuredPrompt(any())).thenReturn(
                Map.of("text", "Test?", "moodContext", "happy", "type", "reflection"));

        AnalyzeMoodResponse response = service.analyzeMood(USER_ID, request);

        assertThat(response.fusedMood()).isEqualTo("happy");
        assertThat(response.sourcesUsed()).containsExactly("MANUAL");
        assertThat(response.modelVersion()).isEqualTo("unavailable");
        verify(aiClient).analyzeMood(request);
    }

    // --------------------------------------------------------------- getMoodEntries

    @Test
    void getMoodEntriesPaginated() {
        List<MoodEntry> entries = List.of(
                createMoodEntity("m-3", USER_ID, "happy"),
                createMoodEntity("m-2", USER_ID, "sad"),
                createMoodEntity("m-1", USER_ID, "neutral"));
        when(repository.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class)))
                .thenReturn(entries);

        List<MoodResponse> result = service.getMoodEntries(USER_ID, 0, 10);

        assertThat(result).hasSize(3);
        assertThat(result.get(0).mood()).isEqualTo("happy");
        assertThat(result.get(1).mood()).isEqualTo("sad");
        assertThat(result.get(2).mood()).isEqualTo("neutral");
        verify(repository).findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class));
    }

    // --------------------------------------------------------------- getRecentMoods

    @Test
    void getRecentMoodsReturnsLimitedEntries() {
        List<MoodEntry> entries = List.of(
                createMoodEntity("r-3", USER_ID, "happy"),
                createMoodEntity("r-2", USER_ID, "calm"),
                createMoodEntity("r-1", USER_ID, "low"));
        when(repository.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class)))
                .thenReturn(entries);

        List<MoodResponse> result = service.getRecentMoods(USER_ID, 3);

        assertThat(result).hasSize(3);
        assertThat(result.get(0).id()).isEqualTo("r-3");
        verify(repository).findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class));
    }

    @Test
    void getRecentMoodsReturnsEmptyWhenNone() {
        when(repository.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class)))
                .thenReturn(List.of());

        List<MoodResponse> result = service.getRecentMoods(USER_ID, 5);

        assertThat(result).isEmpty();
    }

    @Test
    void getRecentMoodsLimitsTo50() {
        when(repository.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class)))
                .thenReturn(List.of());

        // Request 100, should be capped at 50
        service.getRecentMoods(USER_ID, 100);

        verify(repository).findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(Pageable.class));
    }

    // --------------------------------------------------------------- getMoodById

    @Test
    void getMoodByIdWithOwnershipValidation() {
        MoodEntry entry = createMoodEntity(MOOD_ID, USER_ID, "happy");
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.of(entry));

        MoodResponse response = service.getMoodById(USER_ID, MOOD_ID);

        assertThat(response.id()).isEqualTo(MOOD_ID);
        assertThat(response.mood()).isEqualTo("happy");
    }

    @Test
    void getMoodByIdThrowsNotFoundForOtherUsersMood() {
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getMoodById(USER_ID, MOOD_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.NOT_FOUND);
                    assertThat(ex.getMessage()).contains("Mood entry not found");
                });
    }

    @Test
    void getMoodByIdThrowsNotFoundWhenMissing() {
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getMoodById(USER_ID, MOOD_ID))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------------- statistics

    @Test
    void statisticsReturnsEmptyStatsWhenNoEntries() {
        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of());

        MoodStatisticsResponse stats = service.getMoodStatistics(USER_ID);

        assertThat(stats.totalEntries()).isEqualTo(0);
        assertThat(stats.currentStreak()).isEqualTo(0);
        assertThat(stats.longestStreak()).isEqualTo(0);
        assertThat(stats.entriesThisWeek()).isEqualTo(0);
    }

    @Test
    void statisticsCalculatesStreakAndDistribution() {
        Instant now = Instant.now();
        MoodEntry today = createMoodEntity("t1", USER_ID, "happy");
        today.setRecordedAt(now);
        today.setIntensity(8);

        MoodEntry yesterday = createMoodEntity("y1", USER_ID, "calm");
        yesterday.setRecordedAt(now.minus(1, ChronoUnit.DAYS));
        yesterday.setIntensity(5);

        MoodEntry twoDaysAgo = createMoodEntity("d1", USER_ID, "happy");
        twoDaysAgo.setRecordedAt(now.minus(2, ChronoUnit.DAYS));
        twoDaysAgo.setIntensity(7);

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(today, yesterday, twoDaysAgo));

        MoodStatisticsResponse stats = service.getMoodStatistics(USER_ID);

        assertThat(stats.totalEntries()).isEqualTo(3);
        assertThat(stats.entriesThisWeek()).isEqualTo(3);
        assertThat(stats.currentStreak()).isGreaterThanOrEqualTo(3);
        assertThat(stats.longestStreak()).isGreaterThanOrEqualTo(3);
        assertThat(stats.mostCommonMood()).isEqualTo("happy");
        assertThat(stats.averageIntensity()).isEqualTo(6.7);
        assertThat(stats.moodDistribution()).containsEntry("happy", 2L);
        assertThat(stats.moodDistribution()).containsEntry("calm", 1L);
    }

    @Test
    void statisticsEntriesThisWeekOnly() {
        Instant now = Instant.now();
        MoodEntry thisWeek = createMoodEntity("w1", USER_ID, "happy");
        thisWeek.setRecordedAt(now.minus(2, ChronoUnit.DAYS));

        MoodEntry oldEntry = createMoodEntity("o1", USER_ID, "low");
        oldEntry.setRecordedAt(now.minus(30, ChronoUnit.DAYS));

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(thisWeek, oldEntry));

        MoodStatisticsResponse stats = service.getMoodStatistics(USER_ID);

        assertThat(stats.totalEntries()).isEqualTo(2);
        assertThat(stats.entriesThisWeek()).isEqualTo(1);
    }

    // --------------------------------------------------------------- updateMood

    @Test
    void updateMoodSuccessfully() {
        MoodEntry entry = createMoodEntity(MOOD_ID, USER_ID, "sad");
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenReturn(entry);

        UpdateMoodRequest request = new UpdateMoodRequest("happy", "joy", "Feeling better now", null);
        MoodResponse response = service.updateMood(USER_ID, MOOD_ID, request);

        assertThat(response.mood()).isEqualTo("happy");
        assertThat(response.emotion()).isEqualTo("joy");
        assertThat(response.note()).isEqualTo("Feeling better now");
        verify(repository).save(any(MoodEntry.class));
        verify(audit).event(eq(USER_ID), eq("mood.updated"), eq(MOOD_ID));
    }

    @Test
    void updateMoodPartialUpdate() {
        MoodEntry entry = createMoodEntity(MOOD_ID, USER_ID, "sad");
        entry.setEmotion("melancholy");
        entry.setNote("Tough day");
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenReturn(entry);

        UpdateMoodRequest request = new UpdateMoodRequest("calm", null, null, null);
        MoodResponse response = service.updateMood(USER_ID, MOOD_ID, request);

        assertThat(response.mood()).isEqualTo("calm");
        assertThat(response.emotion()).isEqualTo("melancholy");
        assertThat(response.note()).isEqualTo("Tough day");
    }

    @Test
    void updateMoodThrowsNotFoundForOtherUsersMood() {
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.empty());

        UpdateMoodRequest request = new UpdateMoodRequest("happy", null, null, null);
        assertThatThrownBy(() -> service.updateMood(USER_ID, MOOD_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------------- deleteMood

    @Test
    void deleteMoodSuccessfully() {
        MoodEntry entry = createMoodEntity(MOOD_ID, USER_ID, "happy");
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.of(entry));

        service.deleteMood(USER_ID, MOOD_ID);

        verify(repository).delete(entry);
        verify(audit).event(eq(USER_ID), eq("mood.deleted"), eq(MOOD_ID));
    }

    @Test
    void deleteMoodThrowsNotFoundForOtherUsersMood() {
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteMood(USER_ID, MOOD_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.NOT_FOUND);
                    assertThat(ex.getMessage()).contains("Mood entry not found");
                });
        verify(repository, never()).delete(any());
    }

    // --------------------------------------------------------------- getMoodTrends

    @Test
    void getMoodTrendsReturnsMoodDistribution() {
        MoodEntry happy1 = createMoodEntity("h1", USER_ID, "happy");
        happy1.setRecordedAt(Instant.now().minus(1, ChronoUnit.DAYS));
        MoodEntry happy2 = createMoodEntity("h2", USER_ID, "happy");
        happy2.setRecordedAt(Instant.now().minus(2, ChronoUnit.DAYS));
        MoodEntry sad = createMoodEntity("s1", USER_ID, "sad");
        sad.setRecordedAt(Instant.now().minus(1, ChronoUnit.DAYS));

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(happy1, happy2, sad));

        List<MoodTrendResponse> trends = service.getMoodTrends(USER_ID, 7);

        assertThat(trends).hasSize(2);
        assertThat(trends.get(0).mood()).isEqualTo("happy");
        assertThat(trends.get(0).count()).isEqualTo(2);
        assertThat(trends.get(1).mood()).isEqualTo("sad");
        assertThat(trends.get(1).count()).isEqualTo(1);
    }

    @Test
    void getMoodTrendsExcludesOldEntries() {
        // Date-bounded query: only recent entries returned by repository
        MoodEntry recent = createMoodEntity("recent", USER_ID, "happy");
        recent.setRecordedAt(Instant.now().minus(1, ChronoUnit.DAYS));

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(recent));

        List<MoodTrendResponse> trends = service.getMoodTrends(USER_ID, 7);

        assertThat(trends).hasSize(1);
        assertThat(trends.get(0).mood()).isEqualTo("happy");
        assertThat(trends.get(0).count()).isEqualTo(1);
    }

    @Test
    void getMoodTrendsReturnsEmptyWhenNoEntries() {
        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of());

        List<MoodTrendResponse> trends = service.getMoodTrends(USER_ID, 7);

        assertThat(trends).isEmpty();
    }

    @Test
    void getMoodTrendsInsufficientDataReturnsEmpty() {
        MoodEntry single = createMoodEntity("s1", USER_ID, "happy");
        single.setRecordedAt(Instant.now().minus(1, ChronoUnit.DAYS));

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(single));

        List<MoodTrendResponse> trends = service.getMoodTrends(USER_ID, 7);

        assertThat(trends).hasSize(1);
        assertThat(trends.get(0).mood()).isEqualTo("happy");
        assertThat(trends.get(0).count()).isEqualTo(1);
    }

    // --------------------------------------------------------------- enhancedTrends

    @Test
    void enhancedTrendsInsufficientData() {
        // Only 1 entry — below the 3-entry threshold
        MoodEntry single = createMoodEntity("s1", USER_ID, "happy");
        single.setRecordedAt(Instant.now().minus(1, ChronoUnit.DAYS));

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(single));

        Map<String, Object> result = service.getEnhancedTrends(USER_ID, 30);

        assertThat(result.get("status")).isEqualTo("INSUFFICIENT_DATA");
        assertThat(result.get("message").toString())
                .contains("Not enough mood records");
        assertThat(result.get("totalEntries")).isEqualTo(1L);
    }

    @Test
    void enhancedTrendsOkWithSufficientData() {
        MoodEntry e1 = createMoodEntity("e1", USER_ID, "happy");
        e1.setRecordedAt(Instant.now().minus(1, ChronoUnit.DAYS));
        MoodEntry e2 = createMoodEntity("e2", USER_ID, "calm");
        e2.setRecordedAt(Instant.now().minus(2, ChronoUnit.DAYS));
        MoodEntry e3 = createMoodEntity("e3", USER_ID, "low");
        e3.setRecordedAt(Instant.now().minus(3, ChronoUnit.DAYS));

        when(repository.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(
                eq(USER_ID), any(Instant.class), any(Pageable.class)))
                .thenReturn(List.of(e1, e2, e3));

        Map<String, Object> result = service.getEnhancedTrends(USER_ID, 30);

        assertThat(result.get("status")).isEqualTo("OK");
        assertThat(result.get("totalEntries")).isEqualTo(3L);
    }

    // --------------------------------------------------------------- intensity

    @Test
    void createMoodWithIntensity() {
        CreateMoodRequest request = new CreateMoodRequest("happy", "joy", "Great",
                null, "MANUAL", null, null, null, 8);
        when(repository.save(any())).thenAnswer(inv -> {
            MoodEntry entry = inv.getArgument(0);
            entry.setId(MOOD_ID);
            return entry;
        });

        MoodResponse response = service.createMood(USER_ID, request);

        assertThat(response.intensity()).isEqualTo(8);
    }

    @Test
    void createMoodWithInvalidIntensity() {
        assertThatThrownBy(() -> new CreateMoodRequest(
                "happy", "joy", "Great", null, "MANUAL", null, null, null, 11))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Intensity");

        assertThatThrownBy(() -> new CreateMoodRequest(
                "happy", "joy", "Great", null, "MANUAL", null, null, null, 0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Intensity");
    }

    @Test
    void updateMoodSetsIntensity() {
        MoodEntry entry = createMoodEntity(MOOD_ID, USER_ID, "sad");
        when(repository.findByIdAndUserId(MOOD_ID, USER_ID)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenReturn(entry);

        UpdateMoodRequest request = new UpdateMoodRequest("happy", null, null, 9);
        MoodResponse response = service.updateMood(USER_ID, MOOD_ID, request);

        assertThat(response.intensity()).isEqualTo(9);
        verify(repository).save(any(MoodEntry.class));
    }

    @Test
    void updateMoodWithInvalidIntensity() {
        assertThatThrownBy(() -> new UpdateMoodRequest("happy", null, null, 0))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Intensity");

        assertThatThrownBy(() -> new UpdateMoodRequest("happy", null, null, 11))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Intensity");
    }

    @Test
    void updateMoodWithInvalidMoodEnum() {
        assertThatThrownBy(() -> new UpdateMoodRequest("invalid_mood", null, null, null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Mood");
    }

    // --------------------------------------------------------------- helpers

    private static MoodEntry createMoodEntity(String id, String userId, String mood) {
        MoodEntry entry = new MoodEntry();
        entry.setId(id);
        entry.setUserId(userId);
        entry.setMood(mood);
        entry.setEmotion("test-emotion");
        entry.setNote("test-note");
        entry.setRecordedAt(Instant.now());
        entry.setCreatedAt(Instant.now());
        entry.setUpdatedAt(Instant.now());
        return entry;
    }
}
