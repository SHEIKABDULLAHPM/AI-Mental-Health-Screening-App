package com.mindease.backend.wellness.application;

import java.time.Instant;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
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

    public WellnessProfileService(WellnessProfileRepository profiles) {
        this.profiles = profiles;
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
     * the LLM insight narrative (idempotent).
     */
    public WellnessProfile completeFromJob(String userId, String assessmentId,
                                           int wellnessScore, String stressLevel,
                                           int lifestyleScore, String sleepQuality,
                                           String primaryFocus, String aiInsight) {
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
        profile.setUpdatedAt(Instant.now());
        return profiles.save(profile);
    }

    public WellnessProfileDto currentUser(String userId) {
        WellnessProfile profile = profiles.findFirstByUserIdOrderByCreatedAtDesc(userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "No wellness profile yet. Complete your screening first."));
        return WellnessProfileDto.from(profile);
    }
}