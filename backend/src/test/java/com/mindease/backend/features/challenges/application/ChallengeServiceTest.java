package com.mindease.backend.features.challenges.application;

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
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.ChallengeRepository;
import com.mindease.backend.features.challenges.domain.UserChallenge;
import com.mindease.backend.features.challenges.domain.UserChallengeRepository;
import com.mindease.backend.features.challenges.dto.ChallengeResponse;

@ExtendWith(MockitoExtension.class)
class ChallengeServiceTest {

    @Mock
    private ChallengeRepository challengeRepository;

    @Mock
    private UserChallengeRepository userChallengeRepository;

    private ChallengeService service;

    private static final String USER_ID = "user-1";
    private static final String OTHER_USER_ID = "user-2";
    private static final String CHALLENGE_ID = "challenge-1";
    private static final String USER_CHALLENGE_ID = "uc-1";

    @BeforeEach
    void setUp() {
        service = new ChallengeService(challengeRepository, userChallengeRepository);
    }

    // --------------------------------------------------------- getAvailableChallenges

    @Test
    void getAvailableChallengesReturnsActiveChallenges() {
        Challenge c1 = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        Challenge c2 = buildChallenge("challenge-2", "Gratitude Journal", 14, 200, "journal", true);

        when(challengeRepository.findByActiveTrue()).thenReturn(List.of(c1, c2));

        List<ChallengeResponse> results = service.getAvailableChallenges();

        assertThat(results).hasSize(2);
        assertThat(results.get(0).id()).isEqualTo(CHALLENGE_ID);
        assertThat(results.get(0).title()).isEqualTo("Mindfulness Week");
        assertThat(results.get(0).durationDays()).isEqualTo(7);
        assertThat(results.get(0).points()).isEqualTo(100);
        assertThat(results.get(0).isCompleted()).isFalse();
        assertThat(results.get(1).id()).isEqualTo("challenge-2");
    }

    @Test
    void getAvailableChallengesReturnsEmptyListWhenNoneActive() {
        when(challengeRepository.findByActiveTrue()).thenReturn(Collections.emptyList());

        List<ChallengeResponse> results = service.getAvailableChallenges();

        assertThat(results).isEmpty();
    }

    // --------------------------------------------------------- getChallengeById

    @Test
    void getChallengeByIdReturnsChallengeWithUserProgress() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        UserChallenge userChallenge = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 3, false);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(userChallenge));

        ChallengeResponse response = service.getChallengeById(USER_ID, CHALLENGE_ID);

        assertThat(response.id()).isEqualTo(CHALLENGE_ID);
        assertThat(response.title()).isEqualTo("Mindfulness Week");
        assertThat(response.currentDay()).isEqualTo(3);
        assertThat(response.isCompleted()).isFalse();
    }

    @Test
    void getChallengeByIdReturnsChallengeWithoutProgressWhenNotStarted() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.empty());

        ChallengeResponse response = service.getChallengeById(USER_ID, CHALLENGE_ID);

        assertThat(response.id()).isEqualTo(CHALLENGE_ID);
        assertThat(response.currentDay()).isZero();
        assertThat(response.isCompleted()).isFalse();
    }

    @Test
    void getChallengeByIdThrowsNotFoundForInactiveChallenge() {
        when(challengeRepository.findByIdAndActiveTrue("inactive-id"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getChallengeById(USER_ID, "inactive-id"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- startChallenge

    @Test
    void startChallengeCreatesUserChallenge() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.empty());

        UserChallenge saved = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 0, false);
        when(userChallengeRepository.save(any())).thenReturn(saved);

        ChallengeResponse response = service.startChallenge(USER_ID, CHALLENGE_ID);

        assertThat(response.id()).isEqualTo(CHALLENGE_ID);
        assertThat(response.currentDay()).isZero();
        assertThat(response.isCompleted()).isFalse();

        ArgumentCaptor<UserChallenge> captor = ArgumentCaptor.forClass(UserChallenge.class);
        verify(userChallengeRepository).save(captor.capture());
        UserChallenge captured = captor.getValue();
        assertThat(captured.getUserId()).isEqualTo(USER_ID);
        assertThat(captured.getChallengeId()).isEqualTo(CHALLENGE_ID);
        assertThat(captured.getCurrentDay()).isZero();
        assertThat(captured.isCompleted()).isFalse();
        assertThat(captured.getStartedAt()).isNotNull();
        assertThat(captured.getUpdatedAt()).isNotNull();
    }

    @Test
    void startChallengeRejectsIfAlreadyStarted() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        UserChallenge existing = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 2, false);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.startChallenge(USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.BAD_REQUEST);
                    assertThat(ex.getMessage()).contains("already started");
                });

        verify(userChallengeRepository, never()).save(any());
    }

    // --------------------------------------------------------- updateProgress

    @Test
    void updateProgressIncrementsCurrentDay() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 2, false);

        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.save(any())).thenReturn(uc);

        ChallengeResponse response = service.updateProgress(USER_ID, CHALLENGE_ID);

        assertThat(response.currentDay()).isEqualTo(3);
        assertThat(response.isCompleted()).isFalse();

        ArgumentCaptor<UserChallenge> captor = ArgumentCaptor.forClass(UserChallenge.class);
        verify(userChallengeRepository).save(captor.capture());
        assertThat(captor.getValue().getCurrentDay()).isEqualTo(3);
        assertThat(captor.getValue().isCompleted()).isFalse();
        assertThat(captor.getValue().getUpdatedAt()).isNotNull();
    }

    @Test
    void updateProgressMarksCompletedWhenReachingDurationDays() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 3, 100, "meditation", true);
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 2, false);

        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.save(any())).thenReturn(uc);

        ChallengeResponse response = service.updateProgress(USER_ID, CHALLENGE_ID);

        assertThat(response.currentDay()).isEqualTo(3);
        assertThat(response.isCompleted()).isTrue();

        ArgumentCaptor<UserChallenge> captor = ArgumentCaptor.forClass(UserChallenge.class);
        verify(userChallengeRepository).save(captor.capture());
        assertThat(captor.getValue().isCompleted()).isTrue();
        assertThat(captor.getValue().getCompletedAt()).isNotNull();
    }

    @Test
    void updateProgressThrowsNotFoundForOtherUserChallenge() {
        when(userChallengeRepository.findByUserIdAndChallengeId(OTHER_USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateProgress(OTHER_USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(userChallengeRepository, never()).save(any());
    }

    @Test
    void updateProgressRejectsAlreadyCompletedChallenge() {
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 3, true);

        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(uc));

        assertThatThrownBy(() -> service.updateProgress(USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.BAD_REQUEST);
                    assertThat(ex.getMessage()).contains("already completed");
                });

        verify(userChallengeRepository, never()).save(any());
    }

    // --------------------------------------------------------- completeChallenge

    @Test
    void completeChallengeMarksCompleted() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 4, false);

        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));
        when(userChallengeRepository.save(any())).thenReturn(uc);

        ChallengeResponse response = service.completeChallenge(USER_ID, CHALLENGE_ID);

        assertThat(response.isCompleted()).isTrue();
        assertThat(response.currentDay()).isEqualTo(7);

        ArgumentCaptor<UserChallenge> captor = ArgumentCaptor.forClass(UserChallenge.class);
        verify(userChallengeRepository).save(captor.capture());
        UserChallenge saved = captor.getValue();
        assertThat(saved.isCompleted()).isTrue();
        assertThat(saved.getCompletedAt()).isNotNull();
        assertThat(saved.getCurrentDay()).isEqualTo(7);
        assertThat(saved.getUpdatedAt()).isNotNull();
    }

    @Test
    void completeChallengeRejectsAlreadyCompletedChallenge() {
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 7, true);

        when(userChallengeRepository.findByUserIdAndChallengeId(USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.of(uc));

        assertThatThrownBy(() -> service.completeChallenge(USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.BAD_REQUEST);
                    assertThat(ex.getMessage()).contains("already completed");
                });

        verify(userChallengeRepository, never()).save(any());
    }

    @Test
    void completeChallengeThrowsNotFoundForOtherUserChallenge() {
        when(userChallengeRepository.findByUserIdAndChallengeId(OTHER_USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.completeChallenge(OTHER_USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- getActiveChallenges

    @Test
    void getActiveChallengesReturnsIncompleteChallenges() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 3, false);

        when(userChallengeRepository.findByUserIdAndCompletedFalseOrderByStartedAtDesc(USER_ID))
                .thenReturn(List.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));

        List<ChallengeResponse> results = service.getActiveChallenges(USER_ID);

        assertThat(results).hasSize(1);
        assertThat(results.get(0).id()).isEqualTo(CHALLENGE_ID);
        assertThat(results.get(0).currentDay()).isEqualTo(3);
        assertThat(results.get(0).isCompleted()).isFalse();
    }

    @Test
    void getActiveChallengesReturnsEmptyListWhenNoneActive() {
        when(userChallengeRepository.findByUserIdAndCompletedFalseOrderByStartedAtDesc(USER_ID))
                .thenReturn(Collections.emptyList());

        List<ChallengeResponse> results = service.getActiveChallenges(USER_ID);

        assertThat(results).isEmpty();
    }

    @Test
    void getActiveChallengesFiltersOutDeletedChallenges() {
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 3, false);

        when(userChallengeRepository.findByUserIdAndCompletedFalseOrderByStartedAtDesc(USER_ID))
                .thenReturn(List.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.empty());

        List<ChallengeResponse> results = service.getActiveChallenges(USER_ID);

        assertThat(results).isEmpty();
    }

    @Test
    void getActiveChallengesReturnsEmptyForOtherUser() {
        when(userChallengeRepository.findByUserIdAndCompletedFalseOrderByStartedAtDesc(OTHER_USER_ID))
                .thenReturn(Collections.emptyList());

        List<ChallengeResponse> results = service.getActiveChallenges(OTHER_USER_ID);

        assertThat(results).isEmpty();
        verify(challengeRepository, never()).findById(any());
    }

    // --------------------------------------------------------- getCompletedChallenges

    @Test
    void getCompletedChallengesReturnsCompletedChallenges() {
        Challenge challenge = buildChallenge(CHALLENGE_ID, "Mindfulness Week", 7, 100, "meditation", true);
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 7, true);

        when(userChallengeRepository.findByUserIdAndCompletedTrueOrderByCompletedAtDesc(USER_ID))
                .thenReturn(List.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.of(challenge));

        List<ChallengeResponse> results = service.getCompletedChallenges(USER_ID);

        assertThat(results).hasSize(1);
        assertThat(results.get(0).id()).isEqualTo(CHALLENGE_ID);
        assertThat(results.get(0).isCompleted()).isTrue();
        assertThat(results.get(0).currentDay()).isEqualTo(7);
    }

    @Test
    void getCompletedChallengesReturnsEmptyListWhenNoneCompleted() {
        when(userChallengeRepository.findByUserIdAndCompletedTrueOrderByCompletedAtDesc(USER_ID))
                .thenReturn(Collections.emptyList());

        List<ChallengeResponse> results = service.getCompletedChallenges(USER_ID);

        assertThat(results).isEmpty();
    }

    @Test
    void getCompletedChallengesFiltersOutDeletedChallenges() {
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 7, true);

        when(userChallengeRepository.findByUserIdAndCompletedTrueOrderByCompletedAtDesc(USER_ID))
                .thenReturn(List.of(uc));
        when(challengeRepository.findById(CHALLENGE_ID))
                .thenReturn(Optional.empty());

        List<ChallengeResponse> results = service.getCompletedChallenges(USER_ID);

        assertThat(results).isEmpty();
    }

    @Test
    void getCompletedChallengesReturnsEmptyForOtherUser() {
        when(userChallengeRepository.findByUserIdAndCompletedTrueOrderByCompletedAtDesc(OTHER_USER_ID))
                .thenReturn(Collections.emptyList());

        List<ChallengeResponse> results = service.getCompletedChallenges(OTHER_USER_ID);

        assertThat(results).isEmpty();
        verify(challengeRepository, never()).findById(any());
    }

    // --------------------------------------------------------- ownership validation

    @Test
    void updateProgressRejectsForeignUserChallenge() {
        UserChallenge uc = buildUserChallenge(USER_CHALLENGE_ID, USER_ID, CHALLENGE_ID, 2, false);

        when(userChallengeRepository.findByUserIdAndChallengeId(OTHER_USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.updateProgress(OTHER_USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(userChallengeRepository, never()).save(any());
    }

    @Test
    void completeChallengeRejectsForeignUserChallenge() {
        when(userChallengeRepository.findByUserIdAndChallengeId(OTHER_USER_ID, CHALLENGE_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.completeChallenge(OTHER_USER_ID, CHALLENGE_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(userChallengeRepository, never()).save(any());
    }

    // --------------------------------------------------------- helpers

    private static Challenge buildChallenge(
            String id, String title, int durationDays, int points, String type, boolean active) {
        Challenge c = new Challenge();
        c.setId(id);
        c.setTitle(title);
        c.setDescription("A " + durationDays + "-day challenge");
        c.setDurationDays(durationDays);
        c.setPoints(points);
        c.setType(type);
        c.setActive(active);
        c.setCreatedAt(Instant.now());
        c.setUpdatedAt(Instant.now());
        return c;
    }

    private static UserChallenge buildUserChallenge(
            String id, String userId, String challengeId, int currentDay, boolean completed) {
        UserChallenge uc = new UserChallenge();
        uc.setId(id);
        uc.setUserId(userId);
        uc.setChallengeId(challengeId);
        uc.setCurrentDay(currentDay);
        uc.setCompleted(completed);
        uc.setStartedAt(Instant.now());
        uc.setUpdatedAt(Instant.now());
        if (completed) {
            uc.setCompletedAt(Instant.now());
        }
        return uc;
    }
}
