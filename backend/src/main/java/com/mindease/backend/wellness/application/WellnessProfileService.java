package com.mindease.backend.wellness.application;

import java.time.Instant;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.screening.domain.ScreeningRepository;
import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * Creates and serves the wellbeing profile. On assessment submission the
 * server stores a {@code AI_ANALYSIS_PENDING} profile and queues an AI job;
 * once the AI service completes the job the profile is finalized with the
 * deterministic scores and the LLM insight.
 */
@Service
public class WellnessProfileService {

    private final WellnessProfileRepository profiles;
    private final ScreeningRepository screenings;

    public WellnessProfileService(WellnessProfileRepository profiles,
                                  ScreeningRepository screenings) {
        this.profiles = profiles;
        this.screenings = screenings;
    }

    /** Creates the pending profile after a completed assessment (idempotent). */
    public WellnessProfile ensurePendingFor(String userId, String assessmentId) {
        try {
            return profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                    .orElseGet(() -> {
                        WellnessProfile profile = new WellnessProfile();
                        profile.setUserId(userId);
                        profile.setAssessmentId(assessmentId);
                        profile.setStatus(ProfileStatus.AI_ANALYSIS_PENDING);
                        profile.setCreatedAt(Instant.now());
                        profile.setUpdatedAt(Instant.now());
                        return profiles.save(profile);
                    });
        } catch (org.springframework.dao.DuplicateKeyException exc) {
            // Concurrent submission raced us to create the profile; reuse it.
            return profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                    .orElseThrow(() -> new IllegalStateException(
                            "Wellness profile creation raced concurrently.", exc));
        }
    }

    /**
     * Attaches the onboarding mood snapshot to the (possibly still pending)
     * profile so the final assessment can show mood state even before AI
     * completion. Never overwrites deterministic scores or AI insight.
     */
    public WellnessProfile attachMoodSnapshot(String userId, String assessmentId,
                                             WellnessAnalysisService.MoodSummary mood) {
        if (mood == null) {
            return profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                    .orElseGet(() -> ensurePendingFor(userId, assessmentId));
        }
        WellnessProfile profile = profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                .orElseGet(() -> {
                    WellnessProfile created = new WellnessProfile();
                    created.setUserId(userId);
                    created.setAssessmentId(assessmentId);
                    created.setStatus(ProfileStatus.AI_ANALYSIS_PENDING);
                    created.setCreatedAt(Instant.now());
                    return created;
                });
        if (!userId.equals(profile.getUserId())) {
            throw new ApiException(ErrorCode.NOT_FOUND, "Wellness profile not found.");
        }
        profile.setMoodMood(mood.mood());
        profile.setMoodEmotion(mood.emotion());
        profile.setMoodIntensity(mood.intensity());
        profile.setMoodScore(mood.moodScore());
        profile.setMoodTrendDirection(mood.trendDirection());
        profile.setMoodTrendDescription(mood.trendDescription());
        profile.setMoodHistoryCount(mood.historyCount());
        profile.setCameraEmotion(mood.cameraEmotion());
        profile.setCameraConfidence(mood.cameraConfidence());
        profile.setSignalAgreement(mood.signalAgreement());
        profile.setUpdatedAt(Instant.now());
        return profiles.save(profile);
    }

    /**
     * Persists the deterministic scores the moment the assessment is submitted,
     * without waiting for the AI job.
     *
     * <p>The scores are a pure function of the stored questionnaire answers, so
     * withholding them behind an LLM call would let a third-party outage deny
     * the user their own results. Publishing them here keeps the backend the
     * single source of truth and makes the score readable while the insight is
     * still being generated. {@link #completeFromJob} later re-applies the same
     * values together with {@code aiInsight}, so this is idempotent.</p>
     *
     * <p>Never touches {@code aiInsight} and never changes the status - the AI
     * job owns both.</p>
     */
    public WellnessProfile attachDeterministicScores(String userId, String assessmentId,
                                                     int wellnessScore, String stressLevel,
                                                     int lifestyleScore, String sleepQuality,
                                                     String primaryFocus) {
        return attachDeterministicScores(userId, assessmentId, wellnessScore, stressLevel,
                lifestyleScore, sleepQuality, primaryFocus, false);
    }

    /**
     * Same as above, additionally publishing the PHQ-9 item-9 safety flag.
     * Kept as an overload so existing callers and older tests stay source
     * compatible; absence of the flag is treated as "no escalation".
     */
    public WellnessProfile attachDeterministicScores(String userId, String assessmentId,
                                                     int wellnessScore, String stressLevel,
                                                     int lifestyleScore, String sleepQuality,
                                                     String primaryFocus, boolean safetyFlag) {
        WellnessProfile profile = profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                .orElseGet(() -> {
                    WellnessProfile created = new WellnessProfile();
                    created.setUserId(userId);
                    created.setAssessmentId(assessmentId);
                    created.setStatus(ProfileStatus.AI_ANALYSIS_PENDING);
                    created.setCreatedAt(Instant.now());
                    return created;
                });
        if (!userId.equals(profile.getUserId())) {
            throw new ApiException(ErrorCode.NOT_FOUND, "Wellness profile not found.");
        }
        profile.setWellnessScore(wellnessScore);
        profile.setStressLevel(stressLevel);
        profile.setLifestyleScore(lifestyleScore);
        profile.setSleepQuality(sleepQuality);
        profile.setPrimaryFocus(primaryFocus);
        profile.setSafetyFlag(safetyFlag);
        profile.setUpdatedAt(Instant.now());
        return profiles.save(profile);
    }

    /**
     * Persists the analysis result for the assessment, completing the profile.
     * Creates the profile row if it does not exist yet (idempotent).
     */
    public WellnessProfile completeFor(String userId, String assessmentId,
                                       WellnessAnalysisService.Analysis analysis) {
        WellnessProfile profile = profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                .orElseGet(WellnessProfile::new);
        if (profile.getCreatedAt() == null) {
            profile.setCreatedAt(Instant.now());
        }
        profile.setUserId(userId);
        profile.setAssessmentId(assessmentId);
        profile.setStatus(ProfileStatus.COMPLETED);
        profile.setWellnessScore(analysis.wellnessScore());
        profile.setStressLevel(analysis.stressLevel());
        profile.setLifestyleScore(analysis.lifestyleScore());
        profile.setSleepQuality(analysis.sleepQuality());
        profile.setPrimaryFocus(analysis.primaryFocus());
        profile.setAiInsight(analysis.aiInsight());
        profile.setUpdatedAt(Instant.now());
        return profiles.save(profile);
    }

    /**
     * Completes the profile from the AI job result: deterministic scores plus
     * the LLM insight narrative (idempotent). Mood fields already attached via
     * {@link #attachMoodSnapshot} are preserved unless the job carries fresh
     * mood context (non-null), in which case it is applied.
     */
    public WellnessProfile completeFromJob(String userId, String assessmentId,
                                           int wellnessScore, String stressLevel,
                                           int lifestyleScore, String sleepQuality,
                                           String primaryFocus, String aiInsight) {
        return completeFromJob(userId, assessmentId, wellnessScore, stressLevel,
                lifestyleScore, sleepQuality, primaryFocus, aiInsight, null);
    }

    public WellnessProfile completeFromJob(String userId, String assessmentId,
                                           int wellnessScore, String stressLevel,
                                           int lifestyleScore, String sleepQuality,
                                           String primaryFocus, String aiInsight,
                                           WellnessAnalysisService.MoodSummary mood) {
        WellnessProfile profile = profiles.findByUserIdAndAssessmentId(userId, assessmentId)
                .orElseGet(WellnessProfile::new);
        if (profile.getCreatedAt() == null) {
            profile.setCreatedAt(Instant.now());
        }
        profile.setUserId(userId);
        profile.setAssessmentId(assessmentId);
        profile.setStatus(ProfileStatus.COMPLETED);
        profile.setWellnessScore(wellnessScore);
        profile.setStressLevel(stressLevel);
        profile.setLifestyleScore(lifestyleScore);
        profile.setSleepQuality(sleepQuality);
        profile.setPrimaryFocus(primaryFocus);
        profile.setAiInsight(aiInsight);
        if (mood != null) {
            profile.setMoodMood(mood.mood());
            profile.setMoodEmotion(mood.emotion());
            profile.setMoodIntensity(mood.intensity());
            profile.setMoodScore(mood.moodScore());
            profile.setMoodTrendDirection(mood.trendDirection());
            profile.setMoodTrendDescription(mood.trendDescription());
            profile.setMoodHistoryCount(mood.historyCount());
            profile.setCameraEmotion(mood.cameraEmotion());
            profile.setCameraConfidence(mood.cameraConfidence());
            profile.setSignalAgreement(mood.signalAgreement());
        }
        profile.setUpdatedAt(Instant.now());
        return profiles.save(profile);
    }

    public WellnessProfileDto currentUser(String userId) {
        WellnessProfile profile = profiles.findFirstByUserIdOrderByCreatedAtDesc(userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "No wellness profile yet. Complete your screening first."));
        backfillSafetyFlag(profile);
        return WellnessProfileDto.from(profile);
    }

    /**
     * Profiles created before the safety flag existed have no stored value.
     * Derive it once from the linked assessment on read so an existing user
     * with a positive PHQ-9 item 9 is not silently missed. New profiles always
     * carry an explicit value, so this is a one-time repair per profile.
     */
    private void backfillSafetyFlag(WellnessProfile profile) {
        if (profile.getSafetyFlag() != null || profile.getAssessmentId() == null) {
            return;
        }
        screenings.findById(profile.getAssessmentId())
                .filter(screening -> profile.getUserId() != null
                        && profile.getUserId().equals(screening.getUserId()))
                .ifPresent(screening -> {
                    profile.setSafetyFlag(screening.hasSelfHarmSignal());
                    profile.setUpdatedAt(Instant.now());
                    profiles.save(profile);
                });
    }
}