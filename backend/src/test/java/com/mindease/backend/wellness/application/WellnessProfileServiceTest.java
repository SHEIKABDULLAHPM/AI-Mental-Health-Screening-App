package com.mindease.backend.wellness.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
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
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.dto.WellnessProfileDto;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

/**
 * Unit tests for publishing the deterministic scores independently of the AI
 * job.
 *
 * <p>The scores are a pure function of the stored questionnaire answers, so a
 * third-party LLM outage must never hide them from the user. These tests pin
 * the contract that {@code attachDeterministicScores} writes the scores but
 * leaves the insight and the status to the AI job, and that the later
 * completion step re-applies the same values.</p>
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class WellnessProfileServiceTest {

    private static final String USER_ID = "user-1";
    private static final String OTHER_USER_ID = "user-2";
    private static final String ASSESSMENT_ID = "assessment-1";

    @Mock
    private WellnessProfileRepository profiles;

    @Mock
    private com.mindease.backend.screening.domain.ScreeningRepository screenings;

    private WellnessProfileService service;

    @BeforeEach
    void setUp() {
        service = new WellnessProfileService(profiles, screenings);
        when(profiles.save(any(WellnessProfile.class)))
                .thenAnswer(inv -> inv.getArgument(0));
    }

    private WellnessProfile pendingProfile() {
        WellnessProfile profile = new WellnessProfile();
        profile.setId("profile-1");
        profile.setUserId(USER_ID);
        profile.setAssessmentId(ASSESSMENT_ID);
        profile.setStatus(ProfileStatus.AI_ANALYSIS_PENDING);
        profile.setCreatedAt(Instant.now());
        return profile;
    }

    @Test
    void currentUserBackfillsLegacyProfileSafetyFlagFromTheAssessment() {
        WellnessProfile profile = pendingProfile();
        profile.setSafetyFlag(null);
        when(profiles.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(Optional.of(profile));
        com.mindease.backend.screening.domain.Screening screening =
                new com.mindease.backend.screening.domain.Screening();
        screening.setUserId(USER_ID);
        screening.setAssessments(java.util.Map.of(
                "phq9", List.of(0, 0, 0, 0, 0, 0, 0, 0, 2)));
        when(screenings.findById(ASSESSMENT_ID)).thenReturn(Optional.of(screening));

        WellnessProfileDto dto = service.currentUser(USER_ID);

        assertThat(dto.safetyFlag()).isTrue();
        assertThat(profile.getSafetyFlag()).isTrue();
        verify(profiles).save(profile);
    }

    // ── scores are readable before the AI job completes ──

    @Test
    void scoresArePersistedWhileStatusStaysPending() {
        WellnessProfile profile = pendingProfile();
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(profile));

        WellnessProfile saved = service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE");

        assertThat(saved.getWellnessScore()).isEqualTo(58);
        assertThat(saved.getLifestyleScore()).isEqualTo(90);
        assertThat(saved.getStressLevel()).isEqualTo("MODERATE");
        assertThat(saved.getSleepQuality()).isEqualTo("GOOD");
        assertThat(saved.getPrimaryFocus()).isEqualTo("BALANCE");
    }

    @Test
    void publishesThePhq9Item9SafetyFlagWithTheScores() {
        WellnessProfile profile = pendingProfile();
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(profile));

        WellnessProfile saved = service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE", true);

        assertThat(saved.getSafetyFlag()).isTrue();
        assertThat(WellnessProfileDto.from(saved).safetyFlag()).isTrue();
    }

    @Test
    void safetyFlagDefaultsToFalseForLegacyCallers() {
        WellnessProfile profile = pendingProfile();
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(profile));

        WellnessProfile saved = service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE");

        assertThat(saved.getSafetyFlag()).isFalse();
    }

    @Test
    void publishingScoresNeverFlipsStatusOrInventsAnInsight() {
        WellnessProfile profile = pendingProfile();
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(profile));

        WellnessProfile saved = service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE");

        // The AI job owns both of these; publishing scores must not fake either.
        assertThat(saved.getStatus()).isEqualTo(ProfileStatus.AI_ANALYSIS_PENDING);
        assertThat(saved.getAiInsight()).isNull();
    }

    @Test
    void republishingScoresIsIdempotent() {
        WellnessProfile profile = pendingProfile();
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(profile));

        service.attachDeterministicScores(USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE");
        WellnessProfile again = service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE");

        assertThat(again.getWellnessScore()).isEqualTo(58);
        assertThat(again.getStatus()).isEqualTo(ProfileStatus.AI_ANALYSIS_PENDING);
    }

    // ── the AI job still owns the insight and the completion ──

    @Test
    void completingFromJobAppliesTheSameScoresPlusTheInsight() {
        WellnessProfile profile = pendingProfile();
        profile.setWellnessScore(58);
        profile.setStressLevel("MODERATE");
        profile.setLifestyleScore(90);
        profile.setSleepQuality("GOOD");
        profile.setPrimaryFocus("BALANCE");
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(profile));

        WellnessProfile saved = service.completeFromJob(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE",
                "Your sleep is the strongest lever this week.");

        assertThat(saved.getWellnessScore()).isEqualTo(58);
        assertThat(saved.getAiInsight()).isEqualTo("Your sleep is the strongest lever this week.");
        assertThat(saved.getStatus()).isEqualTo(ProfileStatus.COMPLETED);
    }

    // ── ownership ──

    @Test
    void publishingScoresForAnotherUsersProfileIsRejected() {
        WellnessProfile foreign = pendingProfile();
        foreign.setUserId(OTHER_USER_ID);
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.of(foreign));

        assertThatThrownBy(() -> service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 58, "MODERATE", 90, "GOOD", "BALANCE"))
                .isInstanceOf(ApiException.class);
    }

    // ── creation path ──

    @Test
    void publishingScoresCreatesTheProfileAsPendingWhenMissing() {
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.empty());

        WellnessProfile saved = service.attachDeterministicScores(
                USER_ID, ASSESSMENT_ID, 41, "HIGH", 55, "POOR", "SLEEP");

        assertThat(saved.getUserId()).isEqualTo(USER_ID);
        assertThat(saved.getAssessmentId()).isEqualTo(ASSESSMENT_ID);
        assertThat(saved.getWellnessScore()).isEqualTo(41);
        assertThat(saved.getStatus()).isEqualTo(ProfileStatus.AI_ANALYSIS_PENDING);
        assertThat(saved.getCreatedAt()).isNotNull();
    }

    @Test
    void pendingProfileAlreadyExistsAfterEnsure() {
        when(profiles.findByUserIdAndAssessmentId(USER_ID, ASSESSMENT_ID))
                .thenReturn(Optional.empty());

        WellnessProfile created = service.ensurePendingFor(USER_ID, ASSESSMENT_ID);

        assertThat(created.getStatus()).isEqualTo(ProfileStatus.AI_ANALYSIS_PENDING);
        assertThat(created.getWellnessScore()).isNull();
        assertThat(created.getAiInsight()).isNull();
    }
}