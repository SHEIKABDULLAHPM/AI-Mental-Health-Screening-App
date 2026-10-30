package com.mindease.backend.wellness.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.physical.application.PhysicalWellnessAnalysisService;
import com.mindease.backend.features.physical.application.WellnessGoalService;
import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.features.physical.domain.SyncSessionRepository;
import com.mindease.backend.features.physical.dto.PhysicalWellnessAnalysisDto;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.screening.domain.Screening;
import com.mindease.backend.screening.domain.ScreeningRepository;
import com.mindease.backend.screening.domain.ScreeningStatus;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;
import com.mindease.backend.wellness.dto.CombinedWellnessAnalysisDto;
import com.mindease.backend.wellness.dto.MentalWellnessAnalysisDto;

class WellnessAnalysisTargetSyncTest {

    private WellnessGoalService wellnessGoalService;
    private WellnessAnalysisPipeline pipeline;

    @BeforeEach
    void setUp() {
        wellnessGoalService = mock(WellnessGoalService.class);
        pipeline = mock(WellnessAnalysisPipeline.class);

        when(pipeline.run(any(), any(), any(), any(), any(), any(), any(), any(), any()))
                .thenReturn(new WellnessAnalysisPipeline.Outcome(
                        "rec-1",
                        Instant.now(),
                        null,
                        "Narrative insight",
                        List.of("Recommendation 1"),
                        List.of(),
                        List.of("Activity"),
                        List.of("Next action"),
                        "ai"));
    }

    @Test
    void mentalAnalysisAppliesGoalSuggestionsToWellnessGoalService() {
        WellnessProfileRepository profiles = mock(WellnessProfileRepository.class);
        ScreeningRepository screenings = mock(ScreeningRepository.class);
        MoodEntryRepository moodEntries = mock(MoodEntryRepository.class);

        WellnessProfile profile = new WellnessProfile();
        profile.setId("prof-1");
        profile.setUserId("user-1");
        profile.setWellnessScore(65);
        profile.setStressLevel("HIGH");
        profile.setSleepQuality("poor");
        when(profiles.findFirstByUserIdOrderByCreatedAtDesc("user-1")).thenReturn(Optional.of(profile));

        Screening screening = new Screening();
        screening.setId("scr-1");
        screening.setStatus(ScreeningStatus.COMPLETED);
        screening.setUpdatedAt(Instant.now());
        when(screenings.findByUserIdOrderByUpdatedAtDesc("user-1")).thenReturn(List.of(screening));

        MentalWellnessAnalysisService service = new MentalWellnessAnalysisService(
                profiles, screenings, moodEntries, pipeline, wellnessGoalService);

        MentalWellnessAnalysisDto result = service.analyze("user-1");

        assertThat(result.available()).isTrue();
        assertThat(result.goalTargetSuggestions()).isNotEmpty();

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<WellnessGoalDtos.AiRecommendation>> captor =
                ArgumentCaptor.forClass(List.class);
        verify(wellnessGoalService).applyAiRecommendations(eq("user-1"), captor.capture());

        List<WellnessGoalDtos.AiRecommendation> applied = captor.getValue();
        assertThat(applied).anyMatch(r -> "dailySleepMinutes".equals(r.metric()) && r.value() == 480);
        assertThat(applied).anyMatch(r -> "dailyActiveMinutes".equals(r.metric()) && r.value() == 30);
    }

    @Test
    void physicalAnalysisAppliesGoalSuggestionsToWellnessGoalService() {
        DailyActivityRepository dailyActivity = mock(DailyActivityRepository.class);
        HealthReadingRepository healthReadings = mock(HealthReadingRepository.class);
        SleepSessionRepository sleepSessions = mock(SleepSessionRepository.class);
        SyncSessionRepository syncSessions = mock(SyncSessionRepository.class);

        DailyActivity act = new DailyActivity();
        act.setUserId("user-1");
        act.setDate(LocalDate.now());
        act.setSteps(4500);
        act.setActiveMinutes(15);
        when(dailyActivity.findByUserIdAndDateBetweenOrderByDateDesc(eq("user-1"), any(), any()))
                .thenReturn(List.of(act));

        PhysicalWellnessAnalysisService service = new PhysicalWellnessAnalysisService(
                dailyActivity, healthReadings, sleepSessions, syncSessions, pipeline, wellnessGoalService);

        PhysicalWellnessAnalysisDto result = service.analyze("user-1");

        assertThat(result.available()).isTrue();
        assertThat(result.goalTargetSuggestions()).isNotEmpty();

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<WellnessGoalDtos.AiRecommendation>> captor =
                ArgumentCaptor.forClass(List.class);
        verify(wellnessGoalService).applyAiRecommendations(eq("user-1"), captor.capture());

        List<WellnessGoalDtos.AiRecommendation> applied = captor.getValue();
        assertThat(applied).anyMatch(r -> "dailySteps".equals(r.metric()));
        assertThat(applied).anyMatch(r -> "dailyActiveMinutes".equals(r.metric()) && r.value() == 30);
        assertThat(applied).anyMatch(r -> "dailyHydrationMl".equals(r.metric()) && r.value() == 2000);
    }

    @Test
    void combinedAnalysisMergesAndAppliesDeduplicatedGoalSuggestions() {
        MentalWellnessAnalysisService mentalService = mock(MentalWellnessAnalysisService.class);
        PhysicalWellnessAnalysisService physicalService = mock(PhysicalWellnessAnalysisService.class);

        MentalWellnessAnalysisDto mentalDto = new MentalWellnessAnalysisDto(
                "m-1", "MENTAL", Instant.now(), true, 70, "HIGH", 60, "poor", "Sleep",
                "Mental narrative", List.of(), "ai", false, false, null, null, null,
                List.of(), List.of(), List.of(), null,
                List.of(
                        new MentalWellnessAnalysisDto.GoalTargetSuggestion("dailySleepMinutes", 480, "min", "Sleep target"),
                        new MentalWellnessAnalysisDto.GoalTargetSuggestion("dailyActiveMinutes", 30, "min", "Mental active target")
                ));

        PhysicalWellnessAnalysisDto physicalDto = new PhysicalWellnessAnalysisDto(
                "p-1", "PHYSICAL", Instant.now(), true, "ACTIVE",
                null, List.of(), List.of(), "ai", false, null, null, null,
                List.of(), List.of(), List.of(), null, "Physical narrative",
                List.of(
                        new PhysicalWellnessAnalysisDto.GoalTargetSuggestion("dailySteps", 8000, "steps", "Steps target"),
                        new PhysicalWellnessAnalysisDto.GoalTargetSuggestion("dailyActiveMinutes", 45, "min", "Physical measured target")
                ));

        when(mentalService.analyze("user-1")).thenReturn(mentalDto);
        when(physicalService.analyze("user-1")).thenReturn(physicalDto);

        CombinedWellnessAnalysisService service = new CombinedWellnessAnalysisService(
                mentalService, physicalService, pipeline, wellnessGoalService);

        CombinedWellnessAnalysisDto result = service.analyze("user-1");

        assertThat(result.available()).isTrue();
        assertThat(result.goalTargetSuggestions()).hasSize(3); // sleep, steps, active (deduplicated)

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<WellnessGoalDtos.AiRecommendation>> captor =
                ArgumentCaptor.forClass(List.class);
        verify(wellnessGoalService).applyAiRecommendations(eq("user-1"), captor.capture());

        List<WellnessGoalDtos.AiRecommendation> applied = captor.getValue();
        assertThat(applied).hasSize(3);
        // Physical suggestion takes precedence over mental for dailyActiveMinutes
        assertThat(applied).anyMatch(r -> "dailyActiveMinutes".equals(r.metric()) && r.value() == 45);
        assertThat(applied).anyMatch(r -> "dailySteps".equals(r.metric()) && r.value() == 8000);
        assertThat(applied).anyMatch(r -> "dailySleepMinutes".equals(r.metric()) && r.value() == 480);
    }
}
