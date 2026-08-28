package com.mindease.backend.screening.application;

import java.time.Instant;
import java.util.List;

import org.springframework.stereotype.Service;

import com.mindease.backend.ai.application.AiAnalysisJobService;
import com.mindease.backend.ai.domain.AiAnalysisJob;
import com.mindease.backend.ai.domain.DeterministicScores;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.consent.application.ConsentService;
import com.mindease.backend.screening.domain.Screening;
import com.mindease.backend.screening.domain.ScreeningRepository;
import com.mindease.backend.screening.domain.ScreeningStatus;
import com.mindease.backend.screening.dto.ScreeningSubmitResponse;
import com.mindease.backend.user.domain.OnboardingStatus;
import com.mindease.backend.user.domain.User;
import com.mindease.backend.user.domain.UserRepository;
import com.mindease.backend.wellness.application.WellnessAnalysisService;
import com.mindease.backend.wellness.application.WellnessProfileService;
import com.mindease.backend.wellness.domain.WellnessProfile;

/**
 * Assessment workflow: create an in-progress draft, review answers, update
 * them, then submit. Identity is always taken from the authenticated caller -
 * a user can never reach another user's assessment.
 */
@Service
public class ScreeningService {

    public record CreateResult(Screening screening, boolean created) {
    }

    private final ScreeningRepository screenings;
    private final UserRepository users;
    private final ConsentService consents;
    private final WellnessProfileService profiles;
    private final WellnessAnalysisService analysisService;
    private final AiAnalysisJobService aiJobs;
    private final ScreeningValidator validator;
    private final AuditLog audit;

    public ScreeningService(ScreeningRepository screenings,
                            UserRepository users,
                            ConsentService consents,
                            WellnessProfileService profiles,
                            WellnessAnalysisService analysisService,
                            AiAnalysisJobService aiJobs,
                            ScreeningValidator validator,
                            AuditLog audit) {
        this.screenings = screenings;
        this.users = users;
        this.consents = consents;
        this.profiles = profiles;
        this.analysisService = analysisService;
        this.aiJobs = aiJobs;
        this.validator = validator;
        this.audit = audit;
    }

    /**
     * Starts a new assessment for the caller. Idempotent: an existing
     * in-progress assessment is returned instead of creating a duplicate.
     */
    public CreateResult create(String userId, Screening draft) {
        requireConsentCompleted(userId);
        var existing = screenings.findFirstByUserIdAndStatus(userId, ScreeningStatus.IN_PROGRESS);
        if (existing.isPresent()) {
            return new CreateResult(existing.get(), false);
        }

        draft.setId(null);
        draft.setUserId(userId);
        draft.setStatus(ScreeningStatus.IN_PROGRESS);
        draft.setStartedAt(Instant.now());
        draft.setUpdatedAt(Instant.now());
        draft.setCompletedAt(null);
        validator.validateDraft(draft);

        Screening saved = screenings.save(draft);
        users.findById(userId).ifPresent(user -> {
            user.setScreeningStatus(com.mindease.backend.user.domain.ScreeningStatus.IN_PROGRESS);
            user.setUpdatedAt(Instant.now());
            users.save(user);
        });
        audit.event(userId, "assessment.started", saved.getId());
        return new CreateResult(saved, true);
    }

    /** Most recent assessment belonging to the caller, if any. */
    public List<Screening> mine(String userId) {
        return screenings.findByUserIdOrderByUpdatedAtDesc(userId);
    }

    /** Retrieves an assessment owned by the caller only. */
    public Screening getById(String userId, String id) {
        Screening screening = screenings.findById(id)
                .orElseThrow(this::notFound);
        if (!screening.getUserId().equals(userId)) {
            throw notFound();
        }
        return screening;
    }

    /** Updates answers on an in-progress assessment owned by the caller. */
    public Screening update(String userId, String id, Screening draft) {
        Screening existing = getById(userId, id);
        if (existing.getStatus() != ScreeningStatus.IN_PROGRESS) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "This assessment has already been submitted and cannot be edited.");
        }
        existing.setPersonal(draft.getPersonal());
        existing.setLifestyle(draft.getLifestyle());
        existing.setAssessments(draft.getAssessments());
        existing.setUpdatedAt(Instant.now());
        validator.validateDraft(existing);
        return screenings.save(existing);
    }

    /**
     * Validates the complete assessment, marks it completed, queues an
     * asynchronous AI analysis job and returns a pending profile. Duplicate
     * submissions are rejected. The wellness profile stays
     * {@code AI_ANALYSIS_PENDING} until the AI service completes the job.
     *
     * <p>Idempotent and race-safe: a replayed or concurrent submit that finds
     * an existing AI job for the assessment reuses it - exactly one job and
     * one wellness profile are ever created per assessment.</p>
     */
    public ScreeningSubmitResponse submit(String userId, String id) {
        Screening screening = getById(userId, id);

        // A job for this assessment means a previous (or concurrent) submit
        // already ran - never create a second job or wellness profile.
        java.util.Optional<AiAnalysisJob> existingJob = aiJobs.findByAssessmentId(id);
        if (existingJob.isPresent()) {
            if (screening.getStatus() != ScreeningStatus.COMPLETED) {
                completeScreening(userId, screening);
            }
            WellnessProfile profile = profiles.ensurePendingFor(userId, screening.getId());
            return ScreeningSubmitResponse.completed(screening, profile.getStatus(),
                    profile.getId(), existingJob.get().getId());
        }
        if (screening.getStatus() == ScreeningStatus.COMPLETED) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "This assessment has already been submitted.");
        }

        validator.validateComplete(screening);
        Screening saved = completeScreening(userId, screening);

        WellnessProfile profile = profiles.ensurePendingFor(userId, saved.getId());
        WellnessAnalysisService.Scores raw = analysisService.scores(saved);
        WellnessAnalysisService.Analysis analysis = analysisService.analyze(saved);
        AiAnalysisJob job = aiJobs.create(userId, saved.getId(),
                toDeterministicScores(raw, analysis));
        audit.event(userId, "assessment.submitted", saved.getId());

        return ScreeningSubmitResponse.completed(saved, profile.getStatus(),
                profile.getId(), job.getId());
    }

    /** Marks the screening COMPLETED and flips the user's onboarding state. */
    private Screening completeScreening(String userId, Screening screening) {
        screening.setStatus(ScreeningStatus.COMPLETED);
        screening.setCompletedAt(Instant.now());
        screening.setUpdatedAt(Instant.now());
        Screening saved = screenings.save(screening);
        users.findById(userId).ifPresent(user -> {
            user.setScreeningStatus(com.mindease.backend.user.domain.ScreeningStatus.COMPLETED);
            user.setOnboardingStatus(OnboardingStatus.COMPLETED);
            user.setUpdatedAt(Instant.now());
            users.save(user);
        });
        return saved;
    }

    private DeterministicScores toDeterministicScores(
            WellnessAnalysisService.Scores s, WellnessAnalysisService.Analysis a) {
        DeterministicScores scores = new DeterministicScores();
        scores.setPhq9(s.phq9());
        scores.setGad7(s.gad7());
        scores.setPss10(s.pss10());
        scores.setWho5(s.who5());
        scores.setWellnessScore(a.wellnessScore());
        scores.setStressLevel(a.stressLevel());
        scores.setLifestyleScore(a.lifestyleScore());
        scores.setSleepQuality(a.sleepQuality());
        scores.setPrimaryFocus(a.primaryFocus());
        return scores;
    }

    private void requireConsentCompleted(String userId) {
        if (!consents.myConsents(userId).completed()) {
            throw new ApiException(ErrorCode.FORBIDDEN,
                    "Please complete your consents before starting the assessment.");
        }
    }

    private ApiException notFound() {
        return new ApiException(ErrorCode.NOT_FOUND, "Screening not found or no longer available.");
    }
}