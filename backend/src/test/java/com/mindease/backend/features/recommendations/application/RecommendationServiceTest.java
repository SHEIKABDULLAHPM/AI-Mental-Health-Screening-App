package com.mindease.backend.features.recommendations.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.challenges.application.ChallengeActivityService;
import com.mindease.backend.features.recommendations.domain.RecommendationContent;
import com.mindease.backend.features.recommendations.domain.RecommendationContentRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.features.recommendations.dto.FeedbackRequest;
import com.mindease.backend.features.recommendations.dto.InteractionRequest;
import com.mindease.backend.features.recommendations.dto.RecommendationResponse;

@ExtendWith(MockitoExtension.class)
class RecommendationServiceTest {

    @Mock
    private RecommendationContentRepository contentRepo;

    @Mock
    private RecommendationInteractionRepository interactionRepo;

    @Mock
    private RecommendationContextBuilder contextBuilder;

    @Mock
    private RecommendationRankingService rankingService;

    @Mock
    private PersonalizationService personalizationService;

    @Mock
    private ChallengeActivityService challengeActivityService;

    private RecommendationService service;

    @BeforeEach
    void setUp() {
        service = new RecommendationService(contentRepo, interactionRepo, contextBuilder,
                rankingService, personalizationService, challengeActivityService);
    }

    // ── getRecommendations ──

    @Test
    void getRecommendations_returnsRankedResults() {
        when(contextBuilder.buildContext("user-1")).thenReturn(java.util.Map.of());
        RecommendationContent content = buildContent("rec-1", "Meditation", "meditation");
        when(contentRepo.findByActiveTrue()).thenReturn(List.of(content));
        when(rankingService.rank(any(), any())).thenReturn(List.of(
                new RecommendationRankingService.ScoredRecommendation(content, 5.0, "Based on your mood")));

        List<RecommendationResponse> results = service.getRecommendations("user-1", null);

        assertThat(results).hasSize(1);
        assertThat(results.get(0).id()).isEqualTo("rec-1");
        assertThat(results.get(0).title()).isEqualTo("Meditation");
        assertThat(results.get(0).category()).isEqualTo("meditation");
    }

    @Test
    void getRecommendations_withCategoryFilter() {
        when(contextBuilder.buildContext("user-1")).thenReturn(java.util.Map.of());
        RecommendationContent content = buildContent("rec-1", "Breathing", "exercises");
        when(contentRepo.findByActiveTrueAndCategory("exercises")).thenReturn(List.of(content));
        when(rankingService.rank(any(), any())).thenReturn(List.of(
                new RecommendationRankingService.ScoredRecommendation(content, 3.0, "Helpful")));

        List<RecommendationResponse> results = service.getRecommendations("user-1", "exercises");

        assertThat(results).hasSize(1);
        assertThat(results.get(0).category()).isEqualTo("exercises");
    }

    @Test
    void getRecommendations_emptyWhenNoContent() {
        when(contextBuilder.buildContext("user-1")).thenReturn(java.util.Map.of());
        when(contentRepo.findByActiveTrue()).thenReturn(Collections.emptyList());

        List<RecommendationResponse> results = service.getRecommendations("user-1", null);

        assertThat(results).isEmpty();
    }

    // ── getRecommendationById ──

    @Test
    void getRecommendationById_returnsContent() {
        RecommendationContent content = buildContent("rec-1", "Stretching", "exercises");
        when(contentRepo.findByIdAndActiveTrue("rec-1")).thenReturn(Optional.of(content));
        when(contextBuilder.buildContext("user-1")).thenReturn(java.util.Map.of());
        when(rankingService.rank(any(), any())).thenReturn(List.of(
                new RecommendationRankingService.ScoredRecommendation(content, 3.0, "Based on your mood")));

        RecommendationResponse response = service.getRecommendationById("user-1", "rec-1");

        assertThat(response.id()).isEqualTo("rec-1");
        assertThat(response.title()).isEqualTo("Stretching");
    }

    @Test
    void getRecommendationById_throwsForNotFound() {
        when(contentRepo.findByIdAndActiveTrue("missing")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getRecommendationById("user-1", "missing"))
                .isInstanceOf(ApiException.class);
    }

    // ── recordFeedback ──

    @Test
    void recordFeedback_savesInteraction() {
        RecommendationContent content = buildContent("rec-1", "Test", "meditation");
        when(contentRepo.findByIdAndActiveTrue("rec-1")).thenReturn(Optional.of(content));
        when(interactionRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.recordFeedback("user-1", "rec-1", new FeedbackRequest("HELPFUL", null));

        verify(interactionRepo).save(any());
    }

    @Test
    void recordFeedback_idempotentWithRequestId() {
        RecommendationContent content = buildContent("rec-1", "Test", "meditation");
        when(contentRepo.findByIdAndActiveTrue("rec-1")).thenReturn(Optional.of(content));
        when(interactionRepo.findByUserIdAndRequestId("user-1", "req-1"))
                .thenReturn(Optional.of(new com.mindease.backend.features.recommendations.domain.RecommendationInteraction()));

        // Should not throw or save again
        service.recordFeedback("user-1", "rec-1", new FeedbackRequest("HELPFUL", "req-1"));

        verify(interactionRepo, never()).save(any());
    }

    @Test
    void recordFeedback_throwsForInvalidType() {
        assertThatThrownBy(() -> service.recordFeedback("user-1", "rec-1",
                new FeedbackRequest("INVALID", null)))
                .isInstanceOf(ApiException.class);
    }

    // ── recordInteraction ──

    @Test
    void recordInteraction_savesInteraction() {
        RecommendationContent content = buildContent("rec-1", "Test", "meditation");
        when(contentRepo.findByIdAndActiveTrue("rec-1")).thenReturn(Optional.of(content));
        when(interactionRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        service.recordInteraction("user-1", "rec-1", new InteractionRequest("OPENED", null));

        verify(interactionRepo).save(any());
    }

    @Test
    void recordInteraction_throwsForInvalidType() {
        assertThatThrownBy(() -> service.recordInteraction("user-1", "rec-1",
                new InteractionRequest("INVALID", null)))
                .isInstanceOf(ApiException.class);
    }

    // ── helpers ──

    private static RecommendationContent buildContent(String id, String title, String category) {
        RecommendationContent c = new RecommendationContent();
        c.setId(id);
        c.setTitle(title);
        c.setDescription("A wellness activity");
        c.setCategory(category);
        c.setDuration("5 min");
        c.setDifficulty("easy");
        c.setContentReference("/activities/" + id);
        c.setActive(true);
        c.setContentVersion(1);
        c.setCreatedAt(Instant.now());
        c.setUpdatedAt(Instant.now());
        return c;
    }
}
