package com.mindease.backend.wellness.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.application.PhysicalInsightService;
import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.dto.CombinedInsightDto;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

@ExtendWith(MockitoExtension.class)
class CombinedInsightServiceTest {

    private static final String USER = "user-1";

    @Mock
    private WellnessProfileService profiles;
    @Mock
    private PhysicalInsightService physicalInsights;
    @Mock
    private CombinedInsightAiClient aiClient;
    @Mock
    private CombinedInsightCache cache;

    private CombinedInsightService service;

    @BeforeEach
    void setUp() {
        lenient().when(cache.get(anyString(), anyString())).thenReturn(Optional.empty());
        service = new CombinedInsightService(profiles, physicalInsights, aiClient, cache);
    }

    private WellnessProfileDto profile(boolean safetyFlag) {
        WellnessProfile entity = new WellnessProfile();
        entity.setId("profile-1");
        entity.setAssessmentId("assessment-1");
        entity.setStatus(ProfileStatus.COMPLETED);
        entity.setWellnessScore(54);
        entity.setStressLevel("MODERATE");
        entity.setLifestyleScore(64);
        entity.setSleepQuality("FAIR");
        entity.setPrimaryFocus("MOOD_SUPPORT");
        entity.setAiInsight("A stored mental insight.");
        entity.setMoodMood("happy");
        entity.setMoodTrendDirection("stable");
        entity.setSafetyFlag(safetyFlag);
        entity.setCreatedAt(Instant.now());
        return WellnessProfileDto.from(entity);
    }

    private InsightDtos.InsightsResponse physical(boolean sufficient) {
        InsightDtos.DataCoverage coverage = new InsightDtos.DataCoverage(
                14, 6, sufficient ? 5 : 0, 4, 3, 0, List.of("HRV"));
        return new InsightDtos.InsightsResponse(
                Instant.now(), 14, sufficient,
                List.of(new InsightDtos.PatternInsight("sleep_below_baseline", "Sleep",
                        "Sleep below baseline", "ATTENTION", "MEDIUM", List.of(),
                        coverage, "not medical advice")),
                List.of(new InsightDtos.Recommendation("wind_down", "Keep a wind-down",
                        "A short, repeatable wind-down can help.", "SLEEP", "RULE_ENGINE")),
                false, coverage, List.of(), "not medical advice");
    }

    @Test
    void deterministicFallbackUsesOnlyStoredAggregates() {
        when(profiles.currentUser(USER)).thenReturn(profile(false));
        when(physicalInsights.insightsWithoutAi(USER)).thenReturn(physical(true));
        when(aiClient.generate(any(), any()))
                .thenReturn(new CombinedInsightAiClient.Result(false, null, List.of(), null, null));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.available()).isTrue();
        assertThat(dto.generatedBy()).isEqualTo("rules");
        assertThat(dto.narrative()).contains("moderate stress");
        assertThat(dto.narrative()).contains("6 days");
        assertThat(dto.narrative()).contains("not a diagnosis");
        assertThat(dto.suggestions()).extracting(CombinedInsightDto.Suggestion::title)
                .containsExactly("Keep a wind-down");
        assertThat(dto.coverage().daysWithActivity()).isEqualTo(6);
        // The combined path never asks for a second AI wording call.
        verify(physicalInsights).insightsWithoutAi(USER);
        verify(physicalInsights, never()).insights(USER);
        verify(cache).put(eq(USER), anyString(), any());
    }

    @Test
    void aiWordingIsUsedWhenAvailable() {
        when(profiles.currentUser(USER)).thenReturn(profile(false));
        when(physicalInsights.insightsWithoutAi(USER)).thenReturn(physical(true));
        when(aiClient.generate(any(), any())).thenReturn(
                new CombinedInsightAiClient.Result(true, "A grounded AI narrative.",
                        List.of(new CombinedInsightDto.Suggestion("Breathe", "Slow breaths.",
                                "MINDFULNESS")),
                        "llm", "AI note"));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.generatedBy()).isEqualTo("llm");
        assertThat(dto.narrative()).isEqualTo("A grounded AI narrative.");
        assertThat(dto.note()).isEqualTo("AI note");
    }

    @Test
    void safetyEscalationIsAppliedServerSideNotByTheModel() {
        when(profiles.currentUser(USER)).thenReturn(profile(true));
        when(physicalInsights.insightsWithoutAi(USER)).thenReturn(physical(true));
        when(aiClient.generate(any(), any())).thenReturn(
                new CombinedInsightAiClient.Result(true, "A grounded AI narrative.",
                        List.of(new CombinedInsightDto.Suggestion("Breathe", "Slow breaths.",
                                "MINDFULNESS")), "llm", "AI note"));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.safetyFlag()).isTrue();
        assertThat(dto.narrative()).contains("self-harm");
        assertThat(dto.narrative()).contains("crisis service");
        assertThat(dto.suggestions().get(0).category()).isEqualTo("SUPPORT");
        assertThat(dto.suggestions().get(0).description()).contains("trust");
    }

    @Test
    void escalationIsNotRepeatedWhenTheModelAlreadySuggestsSupport() {
        when(profiles.currentUser(USER)).thenReturn(profile(true));
        when(physicalInsights.insightsWithoutAi(USER)).thenReturn(physical(true));
        when(aiClient.generate(any(), any())).thenReturn(
                new CombinedInsightAiClient.Result(true,
                        "It sounds heavy right now — please reach out to someone you trust.",
                        List.of(new CombinedInsightDto.Suggestion("Reach out today",
                                "Tell someone you trust how you are feeling.", "SUPPORT")),
                        "llm", "AI note"));

        CombinedInsightDto dto = service.combined(USER);

        // The crisis line is Java-owned and cannot be suppressed by the model...
        assertThat(dto.narrative()).contains("emergency number");
        assertThat(dto.narrative()).contains("crisis service");
        // ...but the "why" and the outreach advice are not stated twice.
        assertThat(dto.narrative()).doesNotContain("mentioned thoughts of self-harm");
        assertThat(dto.suggestions().stream()
                .filter(item -> "SUPPORT".equals(item.category())).count()).isEqualTo(1);
    }

    @Test
    void escalationKeepsBothSentencesWhenTheModelSaysNothingAboutSupport() {
        assertThat(CombinedInsightService.appendEscalation("A neutral narrative."))
                .isEqualTo("A neutral narrative. " + CombinedInsightService.SAFETY_SUPPORT);
    }

    @Test
    void escalationStillAsksForOutreachWhenTheModelOnlyNamesTheCause() {
        String modelText = "You mentioned thoughts of self-harm, which sounds heavy.";

        String escalation = CombinedInsightService.appendEscalation(modelText);

        // The cause is not repeated, but the actionable request is not lost.
        assertThat(escalation).contains(CombinedInsightService.SAFETY_OUTREACH);
        assertThat(escalation).contains(CombinedInsightService.SAFETY_CRISIS);
        assertThat(escalation.split("mentioned thoughts of self-harm", -1)).hasSize(2);
    }

    @Test
    void escalationIsNotDuplicatedWhenTheModelAlreadyHasACrisisLine() {
        String modelText = "Please reach out to someone you trust. If you are in "
                + "immediate danger, contact your local emergency number.";

        assertThat(CombinedInsightService.appendEscalation(modelText)).isEqualTo(modelText);
    }

    @Test
    void cachedResultSkipsTheAiCall() {
        CombinedInsightDto cached = new CombinedInsightDto(
                Instant.now(), true, "Cached narrative from earlier.",
                List.of(new CombinedInsightDto.Suggestion("Breathe", "Slow breaths.",
                        "MINDFULNESS")),
                "llm", false, "note", true, null);
        when(profiles.currentUser(USER)).thenReturn(profile(false));
        when(physicalInsights.insightsWithoutAi(USER)).thenReturn(physical(true));
        when(cache.get(eq(USER), anyString())).thenReturn(Optional.of(cached));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.cached()).isTrue();
        assertThat(dto.narrative()).isEqualTo("Cached narrative from earlier.");
        verify(aiClient, never()).generate(any(), any());
    }

    @Test
    void pendingProfileIsUnavailableAndNeverComposedFromDefaults() {
        WellnessProfile entity = new WellnessProfile();
        entity.setId("profile-pending");
        entity.setAssessmentId("assessment-1");
        entity.setStatus(ProfileStatus.AI_ANALYSIS_PENDING);
        when(profiles.currentUser(USER)).thenReturn(WellnessProfileDto.from(entity));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.available()).isFalse();
        assertThat(dto.narrative()).isNull();
        verify(physicalInsights, never()).insightsWithoutAi(anyString());
        verify(aiClient, never()).generate(any(), any());
    }

    @Test
    void noProfileReturnsAnUnavailableCardWithoutTouchingPhysicalData() {
        when(profiles.currentUser(USER))
                .thenThrow(new ApiException(ErrorCode.NOT_FOUND, "no profile"));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.available()).isFalse();
        assertThat(dto.narrative()).isNull();
        verify(physicalInsights, never()).insightsWithoutAi(anyString());
    }

    @Test
    void cacheFingerprintChangesWhenCoverageChanges() {
        when(profiles.currentUser(USER)).thenReturn(profile(false));
        when(aiClient.generate(any(), any()))
                .thenReturn(new CombinedInsightAiClient.Result(false, null, List.of(), null, null));
        when(physicalInsights.insightsWithoutAi(USER))
                .thenReturn(physical(true))
                .thenReturn(new InsightDtos.InsightsResponse(
                        Instant.now(), 14, true, List.of(), List.of(), false,
                        new InsightDtos.DataCoverage(14, 1, 0, 2, 1, 0, List.of()),
                        List.of(), "not medical advice"));

        service.combined(USER);
        service.combined(USER);

        org.mockito.ArgumentCaptor<String> fingerprints =
                org.mockito.ArgumentCaptor.forClass(String.class);
        verify(cache, times(2)).put(eq(USER), fingerprints.capture(), any());
        assertThat(fingerprints.getAllValues().get(0))
                .isNotEqualTo(fingerprints.getAllValues().get(1));
    }

    @Test
    void sparsePhysicalDataIsDisclosedInsteadOfInventingAPattern() {
        when(profiles.currentUser(USER)).thenReturn(profile(false));
        when(physicalInsights.insightsWithoutAi(USER)).thenReturn(physical(false));
        when(aiClient.generate(any(), any()))
                .thenReturn(new CombinedInsightAiClient.Result(false, null, List.of(), null, null));

        CombinedInsightDto dto = service.combined(USER);

        assertThat(dto.narrative()).contains("not enough recent physical data");
        assertThat(dto.narrative()).contains("6 of the last 14 days");
        assertThat(dto.narrative()).contains("sleep on 0 nights");
    }
}
