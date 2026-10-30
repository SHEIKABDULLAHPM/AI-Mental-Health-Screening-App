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
import com.mindease.backend.features.mood.application.MoodService;
import com.mindease.backend.screening.domain.MoodAssessment;
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
    private final QuestionnaireCatalogService catalogs;
    private final MoodService moods;

    public ScreeningService(ScreeningRepository screenings,
                            UserRepository users,
                            ConsentService consents,
                            WellnessProfileService profiles,
                            WellnessAnalysisService analysisService,
                            AiAnalysisJobService aiJobs,
                            ScreeningValidator validator,
                            AuditLog audit,
                            QuestionnaireCatalogService catalogs,
                            MoodService moods) {
        this.screenings = screenings;
        this.users = users;
        this.consents = consents;
        this.profiles = profiles;
        this.analysisService = analysisService;
        this.aiJobs = aiJobs;
        this.validator = validator;
        this.audit = audit;
        this.catalogs = catalogs;
        this.moods = moods;
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
        draft.setCatalogVersion(catalogs.current().getVersion());
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
        // Explicit null sections mean "no change" — never wipe stored answers
        // with a partial/degenerate payload (validated below either way).
        if (draft.getPersonal() != null) {
            existing.setPersonal(draft.getPersonal());
        }
        if (draft.getLifestyle() != null) {
            existing.setLifestyle(draft.getLifestyle());
        }
        if (draft.getAssessments() != null) {
            existing.setAssessments(draft.getAssessments());
        }
        if (draft.getMood() != null) {
            existing.setMood(mergeMood(existing.getMood(), draft.getMood()));
        }
        // Answers may be edited under a newer catalog — restamp server-side.
        existing.setCatalogVersion(catalogs.current().getVersion());
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
     *
     * <p>The deterministic scores are published to the profile immediately,
     * before the AI job runs, so they are readable even while the insight is
     * pending. The status stays {@code AI_ANALYSIS_PENDING} until the AI
     * service completes the job and supplies {@code aiInsight}.</p>
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
            // Re-publish the deterministic scores on a replay. Profiles created
            // before scores were published at submit time (or interrupted by a
            // failure) get repaired here, so a user who has an existing job can
            // still obtain their results without an LLM round-trip.
            publishDeterministicScores(userId, screening);
            // Best-effort mood backfill for replays where the first submit
            // attached no snapshot; never creates a second job or profile.
            try {
                WellnessAnalysisService.MoodSummary replayMood = resolveMoodSummary(userId, screening);
                if (replayMood != null) {
                    profiles.attachMoodSnapshot(userId, screening.getId(), replayMood);
                }
            } catch (Exception ignored) {
                // Reuse path stays intact without mood context.
            }
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
        // Publish the deterministic scores now rather than withholding them
        // behind the AI job: they are a pure function of the stored answers, so
        // an LLM outage must never cost the user their own results. The job
        // later adds only the insight narrative and flips the status.
        publishDeterministicScores(userId, saved);
        // Reuse the existing mood history + trend calculation (single source of
        // truth). Failures here never block the assessment — the profile and
        // AI job proceed with deterministic scores and no mood context.
        WellnessAnalysisService.MoodSummary moodSummary = resolveMoodSummary(userId, saved);
        if (moodSummary != null) {
            try {
                profiles.attachMoodSnapshot(userId, saved.getId(), moodSummary);
            } catch (Exception ignored) {
                // Pending profile stays usable without the mood snapshot.
            }
        }
        AiAnalysisJob job = aiJobs.create(userId, saved.getId(),
                toDeterministicScores(raw, analysis, moodSummary));
        audit.event(userId, "assessment.submitted", saved.getId());

        return ScreeningSubmitResponse.completed(saved, profile.getStatus(),
                profile.getId(), job.getId());
    }

    /**
     * Publishes the deterministic scores onto the profile so they are readable
     * without waiting for the AI job. Best-effort: if the write fails the job
     * is still queued and re-applies the same values on completion, so the user
     * keeps a path to their results either way.
     */
    private void publishDeterministicScores(String userId, Screening screening) {
        try {
            WellnessAnalysisService.Analysis analysis = analysisService.analyze(screening);
            profiles.attachDeterministicScores(userId, screening.getId(),
                    analysis.wellnessScore(), analysis.stressLevel(),
                    analysis.lifestyleScore(), analysis.sleepQuality(),
                    analysis.primaryFocus(), screening.hasSelfHarmSignal());
        } catch (Exception ignored) {
            // Deterministic scores are also carried in the AI job payload and
            // re-applied when the job completes.
        }
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
            WellnessAnalysisService.Scores s, WellnessAnalysisService.Analysis a,
            WellnessAnalysisService.MoodSummary mood) {
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
        if (mood != null) {
            scores.setOnboardingMood(mood.mood());
            scores.setOnboardingMoodScore(mood.moodScore());
            scores.setOnboardingMoodEmotion(mood.emotion());
            scores.setOnboardingMoodIntensity(mood.intensity());
            scores.setMoodTrendDirection(mood.trendDirection());
            scores.setMoodTrendDescription(mood.trendDescription());
            scores.setMoodHistoryCount(mood.historyCount());
            scores.setCameraEmotion(mood.cameraEmotion());
            scores.setCameraConfidence(mood.cameraConfidence());
            scores.setCameraModelVersion(mood.cameraModelVersion());
            scores.setSignalAgreement(mood.signalAgreement());
        }
        return scores;
    }

    /**
     * Resolves the onboarding mood summary from the screening snapshot plus
     * the user's existing mood history. The linked mood entry (if any) is
     * ownership-checked and its CAMERA AI observation is extracted as the
     * supporting camera signal — raw client fields are never trusted, and a
     * foreign or deleted id degrades to history-only (no leakage, no
     * failure). Returns null when no onboarding mood was provided; callers
     * degrade gracefully.
     */
    private WellnessAnalysisService.MoodSummary resolveMoodSummary(String userId, Screening screening) {
        MoodAssessment mood = screening.getMood();
        if (mood == null || mood.getCurrentMood() == null || mood.getCurrentMood().isBlank()) {
            return null;
        }
        WellnessAnalysisService.CameraSignal camera = null;
        if (mood.getLinkedMoodEntryId() != null && !mood.getLinkedMoodEntryId().isBlank()) {
            try {
                com.mindease.backend.features.mood.dto.MoodResponse entry =
                        moods.getMoodById(userId, mood.getLinkedMoodEntryId());
                camera = extractCameraSignal(entry);
            } catch (Exception ignored) {
                // Fall through with history-only trend; the snapshot remains valid.
            }
        }
        java.util.Map<String, Object> trends;
        try {
            trends = moods.getEnhancedTrends(userId, 30);
        } catch (Exception ignored) {
            trends = java.util.Map.of(
                    "trend", java.util.Map.of(
                            "direction", "unknown",
                            "description", "Mood history is currently unavailable.",
                            "dataPoints", 0),
                    "totalEntries", 0L);
        }
        Object trendObj = trends.get("trend");
        java.util.Map<String, Object> trendMap = trendObj instanceof java.util.Map<?, ?> m
                ? uncheckedTrend(m) : java.util.Map.of(
                        "direction", "unknown",
                        "description", "Not enough mood records to determine a trend.",
                        "dataPoints", 0);
        int historyCount = 0;
        Object total = trends.get("totalEntries");
        if (total instanceof Number n) {
            historyCount = n.intValue();
        }
        try {
            return analysisService.moodSummary(mood, trendMap, historyCount, camera);
        } catch (Exception ignored) {
            return null;
        }
    }

    /**
     * Extracts the camera supporting signal from a linked mood entry's AI
     * observations. Only observations the fusion pipeline itself produced
     * (source CAMERA) qualify; TEXT observations, unknown emotions, and
     * missing data yield null (no signal) rather than a fabricated one.
     */
    private WellnessAnalysisService.CameraSignal extractCameraSignal(
            com.mindease.backend.features.mood.dto.MoodResponse entry) {
        if (entry == null || entry.aiObservations() == null) {
            return null;
        }
        for (com.mindease.backend.features.mood.dto.MoodResponse.AiObservationDto obs
                : entry.aiObservations()) {
            if (obs != null && "CAMERA".equals(obs.source())
                    && obs.emotion() != null && !obs.emotion().isBlank()
                    && !"unknown".equalsIgnoreCase(obs.emotion())) {
                return new WellnessAnalysisService.CameraSignal(
                        obs.emotion(), obs.confidence(), obs.modelVersion());
            }
        }
        return null;
    }

    @SuppressWarnings("unchecked")
    private java.util.Map<String, Object> uncheckedTrend(java.util.Map<?, ?> raw) {
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        raw.forEach((k, v) -> out.put(String.valueOf(k), v));
        return out;
    }

    /**
     * Merges a partial mood draft into the stored snapshot. Explicit nulls mean
     * "no change" so autosave payloads never wipe previously stored answers.
     */
    private MoodAssessment mergeMood(MoodAssessment existing, MoodAssessment draft) {
        MoodAssessment base = existing != null ? existing : new MoodAssessment();
        if (draft.getCurrentMood() != null) {
            base.setCurrentMood(draft.getCurrentMood());
        }
        if (draft.getEmotion() != null) {
            base.setEmotion(draft.getEmotion());
        }
        if (draft.getIntensity() != null) {
            base.setIntensity(draft.getIntensity());
        }
        if (draft.getNote() != null) {
            base.setNote(draft.getNote());
        }
        if (draft.getFrequency() != null) {
            base.setFrequency(draft.getFrequency());
        }
        if (draft.getRecentChange() != null) {
            base.setRecentChange(draft.getRecentChange());
        }
        if (draft.getContext() != null) {
            base.setContext(draft.getContext());
        }
        if (draft.getLinkedMoodEntryId() != null) {
            base.setLinkedMoodEntryId(draft.getLinkedMoodEntryId());
        }
        return base;
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