package com.mindease.backend.features.relax.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
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
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.application.ChallengeActivityService;
import com.mindease.backend.features.relax.domain.RelaxActivity;
import com.mindease.backend.features.relax.domain.RelaxActivityRepository;
import com.mindease.backend.features.relax.domain.UserRelaxCompletion;
import com.mindease.backend.features.relax.domain.UserRelaxCompletionRepository;
import com.mindease.backend.features.relax.dto.RelaxActivityResponse;

@ExtendWith(MockitoExtension.class)
class RelaxServiceTest {

    @Mock
    private RelaxActivityRepository activityRepository;

    @Mock
    private UserRelaxCompletionRepository completionRepository;

    @Mock
    private ChallengeActivityService challengeActivityService;

    private RelaxService service;

    private static final String USER_ID = "user-1";
    private static final String ACTIVITY_ID = "activity-1";

    @BeforeEach
    void setUp() {
        service = new RelaxService(activityRepository, completionRepository, challengeActivityService);
    }

    // --------------------------------------------------------- getActivities

    @Test
    void getActivitiesReturnsAllActiveWhenNoCategory() {
        RelaxActivity a1 = buildActivity(ACTIVITY_ID, "Deep Breathing", "breathing", 5);
        RelaxActivity a2 = buildActivity("activity-2", "Body Scan", "meditation", 10);
        when(activityRepository.findByActiveTrueOrderByCategoryAscTitleAsc())
                .thenReturn(List.of(a1, a2));
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.empty());
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq("activity-2"), any(), any()))
                .thenReturn(Optional.empty());

        List<RelaxActivityResponse> activities = service.getActivities(USER_ID, Optional.empty());

        assertThat(activities).hasSize(2);
        assertThat(activities.get(0).id()).isEqualTo(ACTIVITY_ID);
        assertThat(activities.get(0).completedByUser()).isFalse();
        assertThat(activities.get(1).id()).isEqualTo("activity-2");
        assertThat(activities.get(1).completedByUser()).isFalse();
    }

    @Test
    void getActivitiesReturnsEmptyWhenNoActiveActivities() {
        when(activityRepository.findByActiveTrueOrderByCategoryAscTitleAsc())
                .thenReturn(Collections.emptyList());

        List<RelaxActivityResponse> activities = service.getActivities(USER_ID, Optional.empty());

        assertThat(activities).isEmpty();
    }

    @Test
    void getActivitiesWithCategoryFilter() {
        RelaxActivity a1 = buildActivity(ACTIVITY_ID, "Deep Breathing", "breathing", 5);
        when(activityRepository.findByActiveTrueAndCategoryOrderByTitleAsc("breathing"))
                .thenReturn(List.of(a1));
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.empty());

        List<RelaxActivityResponse> activities = service.getActivities(
                USER_ID, Optional.of("breathing"));

        assertThat(activities).hasSize(1);
        assertThat(activities.get(0).category()).isEqualTo("breathing");
        verify(activityRepository).findByActiveTrueAndCategoryOrderByTitleAsc("breathing");
        verify(activityRepository, never()).findByActiveTrueOrderByCategoryAscTitleAsc();
    }

    @Test
    void getActivitiesWithBlankCategoryFallsBackToAll() {
        RelaxActivity a1 = buildActivity(ACTIVITY_ID, "Stretch", "movement", 10);
        when(activityRepository.findByActiveTrueOrderByCategoryAscTitleAsc())
                .thenReturn(List.of(a1));
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.empty());

        List<RelaxActivityResponse> activities = service.getActivities(
                USER_ID, Optional.of("  "));

        assertThat(activities).hasSize(1);
        verify(activityRepository).findByActiveTrueOrderByCategoryAscTitleAsc();
        verify(activityRepository, never()).findByActiveTrueAndCategoryOrderByTitleAsc(any());
    }

    @Test
    void getActivitiesMarksCompletedToday() {
        RelaxActivity a1 = buildActivity(ACTIVITY_ID, "Meditate", "meditation", 10);
        when(activityRepository.findByActiveTrueOrderByCategoryAscTitleAsc())
                .thenReturn(List.of(a1));
        UserRelaxCompletion completion = new UserRelaxCompletion();
        completion.setId("comp-1");
        completion.setUserId(USER_ID);
        completion.setActivityId(ACTIVITY_ID);
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.of(completion));

        List<RelaxActivityResponse> activities = service.getActivities(USER_ID, Optional.empty());

        assertThat(activities).hasSize(1);
        assertThat(activities.get(0).completedByUser()).isTrue();
    }

    // --------------------------------------------------------- getActivityById

    @Test
    void getActivityByIdReturnsActivityWithCompletionStatus() {
        RelaxActivity activity = buildActivity(ACTIVITY_ID, "Deep Breathing", "breathing", 5);
        when(activityRepository.findByIdAndActiveTrue(ACTIVITY_ID))
                .thenReturn(Optional.of(activity));
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.empty());

        RelaxActivityResponse response = service.getActivityById(USER_ID, ACTIVITY_ID);

        assertThat(response.id()).isEqualTo(ACTIVITY_ID);
        assertThat(response.title()).isEqualTo("Deep Breathing");
        assertThat(response.category()).isEqualTo("breathing");
        assertThat(response.durationMinutes()).isEqualTo(5);
        assertThat(response.completedByUser()).isFalse();
    }

    @Test
    void getActivityByIdReturnsCompletedStatusWhenDoneToday() {
        RelaxActivity activity = buildActivity(ACTIVITY_ID, "Meditate", "meditation", 10);
        when(activityRepository.findByIdAndActiveTrue(ACTIVITY_ID))
                .thenReturn(Optional.of(activity));
        UserRelaxCompletion completion = new UserRelaxCompletion();
        completion.setUserId(USER_ID);
        completion.setActivityId(ACTIVITY_ID);
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.of(completion));

        RelaxActivityResponse response = service.getActivityById(USER_ID, ACTIVITY_ID);

        assertThat(response.completedByUser()).isTrue();
    }

    @Test
    void getActivityByIdThrowsNotFoundForNonExistent() {
        when(activityRepository.findByIdAndActiveTrue("missing-id"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getActivityById(USER_ID, "missing-id"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- completeActivity

    @Test
    void completeActivityCreatesCompletionRecord() {
        RelaxActivity activity = buildActivity(ACTIVITY_ID, "Meditate", "meditation", 10);
        when(activityRepository.findByIdAndActiveTrue(ACTIVITY_ID))
                .thenReturn(Optional.of(activity));
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.empty());

        RelaxActivityResponse response = service.completeActivity(USER_ID, ACTIVITY_ID);

        assertThat(response.id()).isEqualTo(ACTIVITY_ID);
        assertThat(response.completedByUser()).isTrue();

        ArgumentCaptor<UserRelaxCompletion> captor = ArgumentCaptor.forClass(UserRelaxCompletion.class);
        verify(completionRepository).save(captor.capture());
        UserRelaxCompletion captured = captor.getValue();
        assertThat(captured.getUserId()).isEqualTo(USER_ID);
        assertThat(captured.getActivityId()).isEqualTo(ACTIVITY_ID);
        assertThat(captured.getCompletedAt()).isNotNull();
    }

    @Test
    void completeActivityPreventsDuplicateCompletionSameDay() {
        RelaxActivity activity = buildActivity(ACTIVITY_ID, "Meditate", "meditation", 10);
        when(activityRepository.findByIdAndActiveTrue(ACTIVITY_ID))
                .thenReturn(Optional.of(activity));
        UserRelaxCompletion existing = new UserRelaxCompletion();
        existing.setUserId(USER_ID);
        existing.setActivityId(ACTIVITY_ID);
        when(completionRepository.findByUserIdAndActivityIdAndCompletedAtBetween(
                eq(USER_ID), eq(ACTIVITY_ID), any(), any()))
                .thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.completeActivity(USER_ID, ACTIVITY_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);

        verify(completionRepository, never()).save(any());
    }

    @Test
    void completeActivityThrowsNotFoundForNonExistentActivity() {
        when(activityRepository.findByIdAndActiveTrue("missing-id"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.completeActivity(USER_ID, "missing-id"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(completionRepository, never()).save(any());
    }

    // --------------------------------------------------------- helpers

    private static RelaxActivity buildActivity(String id, String title, String category,
                                               int durationMinutes) {
        RelaxActivity activity = new RelaxActivity();
        activity.setId(id);
        activity.setTitle(title);
        activity.setCategory(category);
        activity.setDurationMinutes(durationMinutes);
        activity.setDescription("Description for " + title);
        activity.setActive(true);
        activity.setCreatedAt(Instant.now());
        return activity;
    }
}
