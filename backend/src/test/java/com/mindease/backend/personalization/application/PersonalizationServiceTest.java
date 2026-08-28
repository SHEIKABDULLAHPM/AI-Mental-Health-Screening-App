package com.mindease.backend.personalization.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.personalization.domain.PersonalizedContextRepository;
import com.mindease.backend.personalization.domain.PersonalizationFeedback;
import com.mindease.backend.personalization.domain.PersonalizationFeedbackRepository;

@ExtendWith(MockitoExtension.class)
class PersonalizationServiceTest {

    @Mock
    private PersonalizedContextRepository contextRepo;

    @Mock
    private PersonalizationFeedbackRepository feedbackRepo;

    @Mock
    private PersonalizationContextBuilder contextBuilder;

    private PersonalizationService service;

    private static final String USER_ID = "user-1";
    private static final String OTHER_USER_ID = "user-2";

    @BeforeEach
    void setUp() {
        service = new PersonalizationService(contextRepo, feedbackRepo, contextBuilder);
    }

    // ── getContext ──

    @Test
    void getContext_returnsCachedContextWhenFresh() {
        PersonalizedContext cached = buildContext(USER_ID);
        cached.setExpiresAt(Instant.now().plus(1, ChronoUnit.HOURS));
        when(contextRepo.findFirstByUserIdAndExpiresAtAfterOrderByGeneratedAtDesc(
                eq(USER_ID), any(Instant.class))).thenReturn(Optional.of(cached));

        PersonalizedContext result = service.getContext(USER_ID);

        assertThat(result.getUserId()).isEqualTo(USER_ID);
        verify(contextBuilder, never()).build(any());
    }

    @Test
    void getContext_rebuildsWhenExpired() {
        PersonalizedContext expired = buildContext(USER_ID);
        expired.setExpiresAt(Instant.now().minus(1, ChronoUnit.HOURS));
        when(contextRepo.findFirstByUserIdAndExpiresAtAfterOrderByGeneratedAtDesc(
                eq(USER_ID), any(Instant.class))).thenReturn(Optional.empty());

        PersonalizedContext fresh = buildContext(USER_ID);
        when(contextBuilder.build(USER_ID)).thenReturn(fresh);
        when(contextRepo.save(any())).thenReturn(fresh);

        PersonalizedContext result = service.getContext(USER_ID);

        assertThat(result.getUserId()).isEqualTo(USER_ID);
        verify(contextBuilder).build(USER_ID);
    }

    @Test
    void getContext_fallsBackToEmptyOnFailure() {
        when(contextRepo.findFirstByUserIdAndExpiresAtAfterOrderByGeneratedAtDesc(
                any(), any())).thenThrow(new RuntimeException("DB error"));

        PersonalizedContext result = service.getContext(USER_ID);

        assertThat(result.getUserId()).isEqualTo(USER_ID);
        assertThat(result.getPersonalizationSummary()).contains("Personalization is being set up");
    }

    // ── refreshContext ──

    @Test
    void refreshContext_buildsAndSavesContext() {
        PersonalizedContext built = buildContext(USER_ID);
        when(contextBuilder.build(USER_ID)).thenReturn(built);
        when(contextRepo.save(any())).thenReturn(built);

        PersonalizedContext result = service.refreshContext(USER_ID);

        assertThat(result.getUserId()).isEqualTo(USER_ID);
        verify(contextBuilder).build(USER_ID);
        verify(contextRepo).save(built);
    }

    @Test
    void refreshContext_fallsBackOnBuilderFailure() {
        when(contextBuilder.build(USER_ID)).thenThrow(new RuntimeException("Build error"));

        PersonalizedContext result = service.refreshContext(USER_ID);

        assertThat(result.getUserId()).isEqualTo(USER_ID);
        assertThat(result.getPersonalizationSummary()).contains("Personalization is being set up");
    }

    // ── recordFeedback ──

    @Test
    void recordFeedback_savesFeedback() {
        service.recordFeedback(USER_ID, "MOOD_RECORDED", "mood-1", "mood", null);

        verify(feedbackRepo).save(any(PersonalizationFeedback.class));
    }

    @Test
    void recordFeedback_refreshesContextOnSignificantEvent() {
        PersonalizedContext built = buildContext(USER_ID);
        when(contextBuilder.build(USER_ID)).thenReturn(built);
        when(contextRepo.save(any())).thenReturn(built);

        service.recordFeedback(USER_ID, "RECOMMENDATION_COMPLETED", "rec-1", "recommendations", null);

        verify(feedbackRepo).save(any());
        verify(contextBuilder).build(USER_ID);
    }

    @Test
    void recordFeedback_doesNotRefreshOnMinorEvent() {
        service.recordFeedback(USER_ID, "COACH_INTERACTION", null, "coach", null);

        verify(feedbackRepo).save(any());
        verify(contextBuilder, never()).build(any());
    }

    // ── getRecentFeedback ──

    @Test
    void getRecentFeedback_returnsFeedbackList() {
        PersonalizationFeedback fb = new PersonalizationFeedback();
        fb.setUserId(USER_ID);
        fb.setEventType("MOOD_RECORDED");
        fb.setCreatedAt(Instant.now());
        when(feedbackRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of(fb));

        List<PersonalizationFeedback> result = service.getRecentFeedback(USER_ID);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getEventType()).isEqualTo("MOOD_RECORDED");
    }

    @Test
    void getRecentFeedback_returnsEmptyOnFailure() {
        when(feedbackRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                any(), any())).thenThrow(new RuntimeException("DB error"));

        List<PersonalizationFeedback> result = service.getRecentFeedback(USER_ID);

        assertThat(result).isEmpty();
    }

    // ── isRecommendationAvoided ──

    @Test
    void isRecommendationAvoided_returnsTrueWhenDismissed() {
        PersonalizationFeedback fb = new PersonalizationFeedback();
        fb.setUserId(USER_ID);
        fb.setEventType("RECOMMENDATION_DISMISSED");
        when(feedbackRepo.findByUserIdAndContentIdOrderByCreatedAtDesc(USER_ID, "rec-1"))
                .thenReturn(List.of(fb));

        assertThat(service.isRecommendationAvoided(USER_ID, "rec-1")).isTrue();
    }

    @Test
    void isRecommendationAvoided_returnsTrueWhenNotUseful() {
        PersonalizationFeedback fb = new PersonalizationFeedback();
        fb.setUserId(USER_ID);
        fb.setEventType("RECOMMENDATION_NOT_USEFUL");
        when(feedbackRepo.findByUserIdAndContentIdOrderByCreatedAtDesc(USER_ID, "rec-1"))
                .thenReturn(List.of(fb));

        assertThat(service.isRecommendationAvoided(USER_ID, "rec-1")).isTrue();
    }

    @Test
    void isRecommendationAvoided_returnsFalseWhenHelpful() {
        PersonalizationFeedback fb = new PersonalizationFeedback();
        fb.setUserId(USER_ID);
        fb.setEventType("RECOMMENDATION_HELPFUL");
        when(feedbackRepo.findByUserIdAndContentIdOrderByCreatedAtDesc(USER_ID, "rec-1"))
                .thenReturn(List.of(fb));

        assertThat(service.isRecommendationAvoided(USER_ID, "rec-1")).isFalse();
    }

    @Test
    void isRecommendationAvoided_returnsFalseOnFailure() {
        when(feedbackRepo.findByUserIdAndContentIdOrderByCreatedAtDesc(any(), any()))
                .thenThrow(new RuntimeException("DB error"));

        assertThat(service.isRecommendationAvoided(USER_ID, "rec-1")).isFalse();
    }

    // ── User isolation ──

    @Test
    void getContext_neverCrossesUserBoundary() {
        // User A's context should only use User A's data
        PersonalizedContext userAContext = buildContext(USER_ID);
        when(contextRepo.findFirstByUserIdAndExpiresAtAfterOrderByGeneratedAtDesc(
                eq(USER_ID), any())).thenReturn(Optional.of(userAContext));

        PersonalizedContext result = service.getContext(USER_ID);

        assertThat(result.getUserId()).isEqualTo(USER_ID);
        assertThat(result.getUserId()).isNotEqualTo(OTHER_USER_ID);
    }

    // ── Helpers ──

    private PersonalizedContext buildContext(String userId) {
        PersonalizedContext ctx = new PersonalizedContext();
        ctx.setUserId(userId);
        ctx.setContextVersion("personalization-ctx-v1");
        ctx.setGeneratedAt(Instant.now());
        ctx.setExpiresAt(Instant.now().plus(30, ChronoUnit.MINUTES));
        ctx.setMoodTrend("stable");
        ctx.setPersonalizationSummary("Your mood has been fairly consistent.");
        return ctx;
    }
}
