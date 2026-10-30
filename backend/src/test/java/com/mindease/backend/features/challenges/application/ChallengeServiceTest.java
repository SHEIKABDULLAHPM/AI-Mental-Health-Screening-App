package com.mindease.backend.features.challenges.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
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
import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.ChallengeFrequency;
import com.mindease.backend.features.challenges.domain.ChallengeProgressEvent;
import com.mindease.backend.features.challenges.domain.ChallengeProgressEventRepository;
import com.mindease.backend.features.challenges.domain.ChallengeRepository;
import com.mindease.backend.features.challenges.domain.ChallengeStatus;
import com.mindease.backend.features.challenges.domain.ChallengeType;
import com.mindease.backend.features.challenges.domain.UserBadge;
import com.mindease.backend.features.challenges.domain.UserBadgeRepository;
import com.mindease.backend.features.challenges.domain.UserChallenge;
import com.mindease.backend.features.challenges.domain.UserChallengeRepository;
import com.mindease.backend.features.challenges.dto.ChallengeResponse;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizedContext;

@ExtendWith(MockitoExtension.class)
class ChallengeServiceTest {

    @Mock
    private ChallengeRepository challengeRepository;
    @Mock
    private UserChallengeRepository userChallengeRepository;
    @Mock
    private ChallengeProgressEventRepository progressEventRepository;
    @Mock
    private UserBadgeRepository badgeRepository;
    @Mock
    private PersonalizationService personalizationService;
    @Mock
    private MongoTemplate mongoTemplate;

    private ChallengeService service;

    private static final String USER_ID = "user-1";
    private static final String OTHER_USER_ID = "user-2";
    private static final String CHALLENGE_ID = "challenge-1";
    private static final String SOURCE_ID = "mood-123";

    @BeforeEach
    void setUp() {
        service = new ChallengeService(challengeRepository, userChallengeRepository,
                progressEventRepository, badgeRepository, personalizationService, mongoTemplate);
    }

    // ── Activity-driven progress ─────────────────────────────────────

    @Test
    void applyActivityAdvancesOpenInProgressChallenge() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 0, 1,
                ChallengeStatus.IN_PROGRESS);

        when(challengeRepository.findByActiveTrueAndType(ChallengeType.MOOD_CHECK_IN.name()))
                .thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));
        when(progressEventRepository
                .existsByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(USER_ID, CHALLENGE_ID, period, SOURCE_ID))
                .thenReturn(false);

        // Idempotency event insert succeeds, and the progress increment reaches target.
        when(progressEventRepository.save(any(ChallengeProgressEvent.class)))
                .thenReturn(new ChallengeProgressEvent());
        UserChallenge after = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 1, 1, ChallengeStatus.IN_PROGRESS);
        when(mongoTemplate.findAndModify(any(Query.class), any(Update.class),
                any(org.springframework.data.mongodb.core.FindAndModifyOptions.class),
                eq(UserChallenge.class)))
                .thenReturn(after);

        service.applyActivity(USER_ID, ChallengeType.MOOD_CHECK_IN, SOURCE_ID, null);

        verify(progressEventRepository).save(any(ChallengeProgressEvent.class));
    }

    @Test
    void applyActivitySkipsDuplicateSourceRecord() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 0, 1,
                ChallengeStatus.IN_PROGRESS);

        when(challengeRepository.findByActiveTrueAndType(ChallengeType.MOOD_CHECK_IN.name()))
                .thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));
        when(progressEventRepository
                .existsByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(USER_ID, CHALLENGE_ID, period, SOURCE_ID))
                .thenReturn(true);

        service.applyActivity(USER_ID, ChallengeType.MOOD_CHECK_IN, SOURCE_ID, null);

        verify(progressEventRepository, never()).save(any(ChallengeProgressEvent.class));
        verify(mongoTemplate, never()).findAndModify(any(), any(), any(), eq(UserChallenge.class));
    }

    @Test
    void applyActivitySkipsChallengeNotStartedByUser() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);

        when(challengeRepository.findByActiveTrueAndType(ChallengeType.MOOD_CHECK_IN.name()))
                .thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.empty());

        service.applyActivity(USER_ID, ChallengeType.MOOD_CHECK_IN, SOURCE_ID, null);

        verify(progressEventRepository, never()).save(any());
        verify(mongoTemplate, never()).findAndModify(any(), any(), any(), eq(UserChallenge.class));
    }

    @Test
    void applyActivitySkipsCompletedChallenge() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 1, 1,
                ChallengeStatus.COMPLETED);

        when(challengeRepository.findByActiveTrueAndType(ChallengeType.MOOD_CHECK_IN.name()))
                .thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));

        service.applyActivity(USER_ID, ChallengeType.MOOD_CHECK_IN, SOURCE_ID, null);

        verify(progressEventRepository, never()).save(any());
    }

    @Test
    void applyActivityHandlesDuplicateKeyFromRace() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 0, 1,
                ChallengeStatus.IN_PROGRESS);

        when(challengeRepository.findByActiveTrueAndType(ChallengeType.MOOD_CHECK_IN.name()))
                .thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));
        when(progressEventRepository
                .existsByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(USER_ID, CHALLENGE_ID, period, SOURCE_ID))
                .thenReturn(false);
        when(progressEventRepository.save(any(ChallengeProgressEvent.class)))
                .thenThrow(new DuplicateKeyException("dup"));

        service.applyActivity(USER_ID, ChallengeType.MOOD_CHECK_IN, SOURCE_ID, null);

        verify(mongoTemplate, never()).findAndModify(any(), any(), any(), eq(UserChallenge.class));
    }

    // ── Start ────────────────────────────────────────────────────────

    @Test
    void startCreatesActiveInstanceForPeriod() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID)).thenReturn(Optional.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.empty());
        when(userChallengeRepository.save(any(UserChallenge.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        ChallengeResponse resp = service.startChallenge(USER_ID, CHALLENGE_ID, null);

        assertThat(resp.id()).isEqualTo(CHALLENGE_ID);
        assertThat(resp.status()).isEqualTo(ChallengeStatus.ACTIVE.name());
        assertThat(resp.progress()).isZero();
        assertThat(resp.target()).isEqualTo(1);
    }

    @Test
    void startReusesOpenInstanceForSamePeriod() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 0, 1,
                ChallengeStatus.ACTIVE);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID)).thenReturn(Optional.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));

        ChallengeResponse resp = service.startChallenge(USER_ID, CHALLENGE_ID, null);

        assertThat(resp.status()).isEqualTo(ChallengeStatus.ACTIVE.name());
        verify(userChallengeRepository, never()).save(any());
    }

    @Test
    void startThrowsNotFoundForInactiveChallenge() {
        when(challengeRepository.findByIdAndActiveTrue("missing")).thenReturn(Optional.empty());
        try {
            service.startChallenge(USER_ID, "missing", null);
        } catch (ApiException e) {
            assertThat(e.getMessage()).contains("not found");
            return;
        }
        throw new AssertionError("expected ApiException");
    }

    // ── Home & eligibility ───────────────────────────────────────────

    @Test
    void homeFiltersIneligibleChallenges() {
        Challenge journalChallenge = buildChallenge("c-j", "Journal",
                ChallengeType.JOURNALING, ChallengeFrequency.DAILY, 1, "JOURNAL_REFLECTION_1");
        journalChallenge.setEligibilityRule("journal:any");

        when(challengeRepository.findByActiveTrue()).thenReturn(List.of(journalChallenge));
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "MOOD_CHECK_IN"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "JOURNALING"))
                .thenReturn(List.of()); // user has no journal activity → not eligible
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "RELAXATION"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "HEALTHY_ROUTINE"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdOrderByOccurredAtDesc(USER_ID)).thenReturn(List.of());
        when(badgeRepository.findByUserIdOrderByEarnedAtDesc(USER_ID)).thenReturn(List.of());

        var home = service.getHome(USER_ID, null);

        // Ineligible journal challenge must not appear as active or recommended.
        assertThat(home.active()).isEmpty();
        assertThat(home.completed()).isEmpty();
        assertThat(home.recommended()).isNull();
    }

    @Test
    void homeListsActiveAndCompletedChallenges() {
        Challenge daily = buildChallenge("c-d", "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        Challenge completed = buildChallenge("c-w", "Weekly Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.WEEKLY, 5, "MOOD_CONSISTENCY_5");
        daily.setEligibilityRule("always");
        completed.setEligibilityRule("always");

        String period = periodKey(ChallengeFrequency.DAILY);
        String weeklyPeriod = periodKey(ChallengeFrequency.WEEKLY);
        UserChallenge active = buildUserChallenge(USER_ID, "c-d", period, 1, 1, ChallengeStatus.COMPLETED);
        UserChallenge weekly = buildUserChallenge(USER_ID, "c-w", weeklyPeriod, 3, 5, ChallengeStatus.IN_PROGRESS);

        when(challengeRepository.findByActiveTrue()).thenReturn(List.of(daily, completed));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, "c-d", period))
                .thenReturn(Optional.of(active));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, "c-w", weeklyPeriod))
                .thenReturn(Optional.of(weekly));
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "MOOD_CHECK_IN"))
                .thenReturn(buildEvents(5));
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "JOURNALING"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "RELAXATION"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "HEALTHY_ROUTINE"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdOrderByOccurredAtDesc(USER_ID)).thenReturn(buildEvents(5));
        when(badgeRepository.findByUserIdOrderByEarnedAtDesc(USER_ID)).thenReturn(List.of());

        var home = service.getHome(USER_ID, null);

        assertThat(home.completed()).hasSize(1);
        assertThat(home.active()).hasSize(1);
        assertThat(home.active().get(0).progress()).isEqualTo(3);
    }

    // ── Badges ───────────────────────────────────────────────────────

    @Test
    void getBadgesReturnsUserScopedBadges() {
        UserBadge badge = new UserBadge();
        badge.setUserId(USER_ID);
        badge.setCode("MOOD_CHECK_IN_1");
        badge.setLabel("Mood Check-In");
        badge.setChallengeId(CHALLENGE_ID);
        badge.setEarnedAt(Instant.now());

        when(badgeRepository.findByUserIdOrderByEarnedAtDesc(USER_ID)).thenReturn(List.of(badge));

        var badges = service.getBadges(USER_ID);
        assertThat(badges).hasSize(1);
        assertThat(badges.get(0).code()).isEqualTo("MOOD_CHECK_IN_1");
    }

    // ── Expiration ───────────────────────────────────────────────────

    @Test
    void expireIfOverdueTransitionsOpenChallengeToExpired() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 0, 1,
                ChallengeStatus.ACTIVE);
        uc.setExpiresAt(Instant.now().minusSeconds(3600)); // expired 1 hour ago

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID)).thenReturn(Optional.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));
        when(userChallengeRepository.save(any(UserChallenge.class))).thenAnswer(inv -> inv.getArgument(0));

        var resp = service.getChallenge(USER_ID, CHALLENGE_ID, null);

        assertThat(resp.status()).isEqualTo(ChallengeStatus.EXPIRED.name());
        verify(userChallengeRepository).save(any(UserChallenge.class));
    }

    @Test
    void completedChallengeIsNotOverwrittenByExpiration() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 1, 1,
                ChallengeStatus.COMPLETED);
        uc.setCompletedAt(Instant.now());

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID)).thenReturn(Optional.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));

        var resp = service.getChallenge(USER_ID, CHALLENGE_ID, null);

        assertThat(resp.status()).isEqualTo(ChallengeStatus.COMPLETED.name());
        assertThat(resp.completedAt()).isNotNull();
        verify(userChallengeRepository, never()).save(any());
    }

    // ── Completion & Badge ──────────────────────────────────────────

    @Test
    void applyActivityCompletesChallengeAndGrantsBadge() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);
        // Challenge is in progress with 0/1 — one more activity completes it.
        UserChallenge uc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 0, 1,
                ChallengeStatus.IN_PROGRESS);

        when(challengeRepository.findByActiveTrueAndType(ChallengeType.MOOD_CHECK_IN.name()))
                .thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.of(uc));
        when(progressEventRepository
                .existsByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(USER_ID, CHALLENGE_ID, period, SOURCE_ID))
                .thenReturn(false);
        when(progressEventRepository.save(any(ChallengeProgressEvent.class)))
                .thenReturn(new ChallengeProgressEvent());

        // findAndModify: progress increments to 1/1 → completes
        UserChallenge afterProgress = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 1, 1,
                ChallengeStatus.IN_PROGRESS);
        // findAndModify: finalizeCompletion sets COMPLETED
        UserChallenge afterCompletion = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 1, 1,
                ChallengeStatus.COMPLETED);
        afterCompletion.setCompletedAt(Instant.now());

        when(mongoTemplate.findAndModify(any(Query.class), any(Update.class),
                any(org.springframework.data.mongodb.core.FindAndModifyOptions.class),
                eq(UserChallenge.class)))
                .thenReturn(afterProgress)  // first call: advance progress
                .thenReturn(afterCompletion); // second call: finalize completion

        // finalizeCompletion now calls findById to update streak before findAndModify
        UserChallenge streakUc = buildUserChallenge(USER_ID, CHALLENGE_ID, period, 1, 1,
                ChallengeStatus.IN_PROGRESS);
        streakUc.setId("uc-" + CHALLENGE_ID);
        when(userChallengeRepository.findById("uc-" + CHALLENGE_ID))
                .thenReturn(Optional.of(streakUc));

        when(badgeRepository.save(any(UserBadge.class))).thenAnswer(inv -> inv.getArgument(0));

        service.applyActivity(USER_ID, ChallengeType.MOOD_CHECK_IN, SOURCE_ID, null);

        // Badge should have been granted
        verify(badgeRepository).save(any(UserBadge.class));
    }

    // ── IDOR ───────────────────────────────────────────────────────

    @Test
    void startChallengeUsesServerDerivedUserId() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");
        String period = periodKey(ChallengeFrequency.DAILY);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID)).thenReturn(Optional.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(OTHER_USER_ID, CHALLENGE_ID, period))
                .thenReturn(Optional.empty());
        when(userChallengeRepository.save(any(UserChallenge.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        // Start as OTHER_USER_ID — the userId is server-derived, never from the request body
        var resp = service.startChallenge(OTHER_USER_ID, CHALLENGE_ID, null);

        assertThat(resp.id()).isEqualTo(CHALLENGE_ID);
        // Verify the saved UserChallenge has OTHER_USER_ID, not USER_ID
        verify(userChallengeRepository).save(argThat(uc ->
                OTHER_USER_ID.equals(uc.getUserId()) && !USER_ID.equals(uc.getUserId())));
    }

    @Test
    void getHomeReturnsOnlyOwnData() {
        // This test verifies that getHome only queries using the provided userId.
        // Since all repository calls are user-scoped, this is inherently protected.
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");

        when(challengeRepository.findByActiveTrue()).thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, periodKey(ChallengeFrequency.DAILY)))
                .thenReturn(Optional.empty());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "MOOD_CHECK_IN"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "JOURNALING"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "RELAXATION"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "HEALTHY_ROUTINE"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdOrderByOccurredAtDesc(USER_ID)).thenReturn(List.of());
        when(badgeRepository.findByUserIdOrderByEarnedAtDesc(USER_ID)).thenReturn(List.of());

        var home = service.getHome(USER_ID, null);

        // Verify repositories were queried with USER_ID, not OTHER_USER_ID
        verify(userChallengeRepository).findByUserIdAndChallengeIdAndPeriodStart(
                eq(USER_ID), any(), any());
        verify(badgeRepository).findByUserIdOrderByEarnedAtDesc(eq(USER_ID));
    }

    // ── Weekly period ───────────────────────────────────────────────

    @Test
    void startWeeklyChallengeUsesMondayPeriod() {
        Challenge c = buildChallenge(CHALLENGE_ID, "Weekly Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.WEEKLY, 5, "MOOD_CONSISTENCY_5");
        // The weekly period key should be the Monday of the current week
        String expectedPeriod = periodKey(ChallengeFrequency.WEEKLY);

        when(challengeRepository.findByIdAndActiveTrue(CHALLENGE_ID)).thenReturn(Optional.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(USER_ID, CHALLENGE_ID, expectedPeriod))
                .thenReturn(Optional.empty());
        when(userChallengeRepository.save(any(UserChallenge.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        var resp = service.startChallenge(USER_ID, CHALLENGE_ID, null);

        assertThat(resp.target()).isEqualTo(5);
        assertThat(resp.frequency()).isEqualTo(ChallengeFrequency.WEEKLY.name());
        verify(userChallengeRepository).save(argThat(uc ->
                expectedPeriod.equals(uc.getPeriodStart())));
    }

    @Test
    void getChallengeThrowsNotFoundForInactiveChallenge() {
        when(challengeRepository.findByIdAndActiveTrue("nonexistent")).thenReturn(Optional.empty());
        try {
            service.getChallenge(USER_ID, "nonexistent", null);
        } catch (ApiException e) {
            assertThat(e.getMessage()).contains("not found");
            return;
        }
        throw new AssertionError("expected ApiException for missing challenge");
    }

    // ── Streak (via StreakCalculator) ───────────────────────────────

    @Test
    void homeComputesStreakFromProgressEvents() {
        // 3 consecutive days of activity → streak should be 3
        Challenge c = buildChallenge(CHALLENGE_ID, "Daily Mood", ChallengeType.MOOD_CHECK_IN,
                ChallengeFrequency.DAILY, 1, "MOOD_CHECK_IN_1");

        when(challengeRepository.findByActiveTrue()).thenReturn(List.of(c));
        when(userChallengeRepository.findByUserIdAndChallengeIdAndPeriodStart(eq(USER_ID), eq(CHALLENGE_ID), any()))
                .thenReturn(Optional.empty());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "MOOD_CHECK_IN"))
                .thenReturn(buildEvents(3));
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "JOURNALING"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "RELAXATION"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(USER_ID, "HEALTHY_ROUTINE"))
                .thenReturn(List.of());
        when(progressEventRepository.findByUserIdOrderByOccurredAtDesc(USER_ID)).thenReturn(buildEvents(3));
        when(badgeRepository.findByUserIdOrderByEarnedAtDesc(USER_ID)).thenReturn(List.of());

        var home = service.getHome(USER_ID, null);

        assertThat(home.currentStreak()).isEqualTo(3);
    }

    // ── Helpers ──────────────────────────────────────────────────────

    private static Challenge buildChallenge(String id, String title, ChallengeType type,
                                            ChallengeFrequency freq, int target, String badge) {
        Challenge c = new Challenge();
        c.setId(id);
        c.setTitle(title);
        c.setDescription("description");
        c.setType(type.name());
        c.setFrequency(freq.name());
        c.setTarget(target);
        c.setPoints(10);
        c.setReward("reward");
        c.setBadgeCode(badge);
        c.setActive(true);
        c.setCreatedAt(Instant.now());
        c.setUpdatedAt(Instant.now());
        return c;
    }

    private static UserChallenge buildUserChallenge(String userId, String challengeId,
                                                    String period, int progress, int target,
                                                    ChallengeStatus status) {
        UserChallenge uc = new UserChallenge();
        uc.setId("uc-" + challengeId);
        uc.setUserId(userId);
        uc.setChallengeId(challengeId);
        uc.setPeriodStart(period);
        uc.setProgress(progress);
        uc.setTarget(target);
        uc.setStatusEnum(status);
        uc.setStartedAt(Instant.now());
        uc.setUpdatedAt(Instant.now());
        return uc;
    }

    private static List<ChallengeProgressEvent> buildEvents(int n) {
        var events = new java.util.ArrayList<ChallengeProgressEvent>();
        for (int i = 0; i < n; i++) {
            ChallengeProgressEvent e = new ChallengeProgressEvent();
            e.setActivityDate(activityDate(i));
            e.setOccurredAt(Instant.now().minusSeconds(i * 86400L));
            events.add(e);
        }
        return events;
    }

    // ── Time helpers ───────────────────────────────────────────────────────────
    // Period keys and activity dates are derived server-side in UTC by
    // ChallengePeriodCalculator (the default zone when the user has no
    // timezone). Deriving the stubs here through that same helper keeps these
    // tests correct regardless of the timezone of the machine running them.
    // Using the JVM default zone instead made the whole class fail for the five
    // hours after local midnight in any zone ahead of UTC (e.g. IST, UTC+5),
    // because the expected day was already ahead of the UTC day the service
    // computes.
    private static String periodKey(ChallengeFrequency frequency) {
        return ChallengePeriodCalculator.periodKey(
                Instant.now(), frequency, ChallengePeriodCalculator.zone(null));
    }

    private static String activityDate(int daysAgo) {
        return java.time.LocalDate.now(ChallengePeriodCalculator.zone(null))
                .minusDays(daysAgo).toString();
    }
}
