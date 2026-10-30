package com.mindease.backend.ai.application;

import java.time.Instant;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mindease.backend.ai.domain.AiAnalysisJob;
import com.mindease.backend.ai.domain.AiAnalysisJobRepository;
import com.mindease.backend.ai.domain.AiJobStatus;
import com.mindease.backend.ai.domain.DeterministicScores;
import com.mindease.backend.ai.dto.AiAnalysisJobDto;
import com.mindease.backend.ai.dto.AiAnalysisResultRequest;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.config.AppProperties;
import com.mindease.backend.screening.domain.Screening;
import com.mindease.backend.screening.domain.ScreeningRepository;
import com.mindease.backend.wellness.application.WellnessAnalysisService;
import com.mindease.backend.wellness.application.WellnessProfileService;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;

import static java.util.concurrent.TimeUnit.MILLISECONDS;

/**
 * Orchestrates the asynchronous AI job lifecycle:
 *
 * <pre>
 * QUEUED --claim--> PROCESSING --complete--> COMPLETED
 *                          \--fail--> FAILED --retry--> QUEUED
 * </pre>
 *
 * Only the job owner may query status or retry; the AI service interacts with
 * the job through the internal endpoints using the shared internal API key.
 */
@Service
public class AiAnalysisJobService {

    private static final Logger log = LoggerFactory.getLogger(AiAnalysisJobService.class);

    /** Phrasing that would present the insight as a diagnosis (mirrors the AI service). */
    private static final java.util.List<String> DIAGNOSIS_TERMS = java.util.List.of(
            "diagnosed with",
            "suffering from",
            "a diagnosis of",
            "as a patient",
            "patients with",
            "you have depression",
            "you have anxiety disorder",
            "you have ptsd",
            "you have bipolar",
            "you have schizophrenia",
            "you are depressed",
            "you are clinically");

    private final AiAnalysisJobRepository jobs;
    private final RabbitTemplate rabbit;
    private final Queue aiTasksQueue;
    private final AppProperties props;
    private final ObjectMapper objectMapper;
    private final WellnessProfileService profiles;
    private final ScreeningRepository screenings;
    private final WellnessAnalysisService analysis;

    // Metrics
    private final Counter jobsCreated;
    private final Counter jobsCompleted;
    private final Counter jobsFailed;
    private final Counter jobsRetried;
    private final Counter publishFailures;
    private final Timer claimTimer;
    private final Timer completeTimer;
    private final Timer processingDuration;

    public AiAnalysisJobService(AiAnalysisJobRepository jobs,
                                RabbitTemplate rabbit,
                                Queue aiTasksQueue,
                                AppProperties props,
                                ObjectMapper objectMapper,
                                WellnessProfileService profiles,
                                ScreeningRepository screenings,
                                WellnessAnalysisService analysis,
                                MeterRegistry meterRegistry) {
        this.jobs = jobs;
        this.rabbit = rabbit;
        this.aiTasksQueue = aiTasksQueue;
        this.props = props;
        this.objectMapper = objectMapper;
        this.profiles = profiles;
        this.screenings = screenings;
        this.analysis = analysis;

        this.jobsCreated = Counter.builder("ai.jobs.created")
                .description("Number of AI analysis jobs created")
                .register(meterRegistry);
        this.jobsCompleted = Counter.builder("ai.jobs.completed")
                .description("Number of AI analysis jobs completed successfully")
                .register(meterRegistry);
        this.jobsFailed = Counter.builder("ai.jobs.failed")
                .description("Number of AI analysis jobs that failed")
                .register(meterRegistry);
        this.jobsRetried = Counter.builder("ai.jobs.retried")
                .description("Number of AI analysis jobs retried by owner")
                .register(meterRegistry);
        this.publishFailures = Counter.builder("ai.jobs.publish.failures")
                .description("Number of times publishing to RabbitMQ failed")
                .register(meterRegistry);
        this.claimTimer = Timer.builder("ai.jobs.claim.duration")
                .description("Time spent claiming a job")
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(meterRegistry);
        this.completeTimer = Timer.builder("ai.jobs.complete.duration")
                .description("Time spent completing a job")
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(meterRegistry);
        this.processingDuration = Timer.builder("ai.jobs.processing.duration")
                .description("Total processing time from claim to completion")
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(meterRegistry);
    }

    /** Creates a QUEUED job for the completed assessment and enqueues it. */
    @Transactional
    public AiAnalysisJob create(String userId, String assessmentId, DeterministicScores scores) {
        AiAnalysisJob job = new AiAnalysisJob();
        job.setUserId(userId);
        job.setAssessmentId(assessmentId);
        job.setScores(scores);
        job.setStatus(AiJobStatus.QUEUED);
        job.setAttemptCount(0);
        job.setMaxAttempts(props.getAi().getMaxAttempts());
        job.setCreatedAt(Instant.now());
        job.setUpdatedAt(Instant.now());
        AiAnalysisJob saved;
        try {
            saved = jobs.save(job);
        } catch (org.springframework.dao.DuplicateKeyException exc) {
            // A concurrent (or replayed) submission already created the job for
            // this assessment - reuse it rather than creating a duplicate.
            log.warn("ai_job_duplicate_assessment rejected assessmentId={}", assessmentId);
            return jobs.findByAssessmentId(assessmentId)
                    .orElseThrow(() -> new ApiException(ErrorCode.CONFLICT,
                            "This assessment has already been submitted."));
        }
        jobsCreated.increment();
        if (!publish(saved.getId())) {
            saved.setStatus(AiJobStatus.FAILED);
            saved.setErrorMessage("The analysis could not be enqueued. Please retry.");
            saved.setUpdatedAt(Instant.now());
            saved = jobs.save(saved);
            log.error("ai_job_failed_on_publish jobId={}", saved.getId());
        }
        return saved;
    }

    /** Status for the job owner only. */
    public AiAnalysisJobDto statusFor(String userId, String jobId) {
        return AiAnalysisJobDto.from(requireOwned(userId, jobId));
    }

    /** The job already created for an assessment, if any (submit idempotency). */
    public java.util.Optional<AiAnalysisJob> findByAssessmentId(String assessmentId) {
        return jobs.findByAssessmentId(assessmentId);
    }

    /**
     * Re-enqueues a FAILED job for the owner. Only allowed while the job is
     * FAILED and attempts remain; a completed job is never reprocessed.
     */
    @Transactional
    public AiAnalysisJobDto retry(String userId, String jobId) {
        AiAnalysisJob job = requireOwned(userId, jobId);
        if (job.getStatus() == AiJobStatus.COMPLETED) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "This analysis has already completed and cannot be retried.");
        }
        if (job.getStatus() == AiJobStatus.PROCESSING) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "This analysis is still being processed.");
        }
        if (job.getAttemptCount() >= job.getMaxAttempts()) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "The maximum number of retry attempts has been reached.");
        }
        job.setStatus(AiJobStatus.QUEUED);
        job.setErrorMessage(null);
        job.setUpdatedAt(Instant.now());
        jobs.save(job);
        if (!publish(job.getId())) {
            job.setStatus(AiJobStatus.FAILED);
            job.setErrorMessage("The analysis could not be re-enqueued. Please retry.");
            job.setUpdatedAt(Instant.now());
            jobs.save(job);
            throw new ApiException(ErrorCode.UPSTREAM_UNAVAILABLE,
                    "The analysis could not be re-enqueued right now. Please retry.");
        }
        jobsRetried.increment();
        return AiAnalysisJobDto.from(job);
    }

    // ------------------------------------------------------------------ internal

    /**
     * Claims a job for processing by the AI service: transitions QUEUED ->
     * PROCESSING and hands back the deterministic scores (the minimal,
     * anonymized input the LLM is allowed to see).
     */
    public DeterministicScores claim(String jobId) {
        return claimTimer.record(() -> {
            AiAnalysisJob job = requireInternal(jobId);
            if (job.getStatus() == AiJobStatus.COMPLETED) {
                throw new ApiException(ErrorCode.CONFLICT, "Job already completed.");
            }
            if (job.getStatus() == AiJobStatus.FAILED) {
                throw new ApiException(ErrorCode.CONFLICT, "Job failed; retry required.");
            }
            if (job.getStatus() != AiJobStatus.PROCESSING) {
                job.setStatus(AiJobStatus.PROCESSING);
                job.setAttemptCount(job.getAttemptCount() + 1);
                job.setStartedAt(Instant.now());
                job.setUpdatedAt(Instant.now());
                jobs.save(job);
            }
            return job.getScores();
        });
    }

    /**
     * Marks the job COMPLETED and stores the AI result (idempotent).
     * The payload is re-validated server-side so a compromised or buggy
     * AI-service client can never store unpackaged LLM output as a profile
     * insight.
     */
    public AiAnalysisJob complete(String jobId, AiAnalysisResultRequest result) {
        return completeTimer.record(() -> {
            AiAnalysisJob job = requireInternal(jobId);
            if (job.getStatus() == AiJobStatus.COMPLETED) {
                return job;
            }
            if (job.getStatus() != AiJobStatus.PROCESSING) {
                throw new ApiException(ErrorCode.CONFLICT, "Job is not being processed.");
            }
            validateAiInsight(result.aiInsight());
            job.setStatus(AiJobStatus.COMPLETED);
            job.setAiInsight(result.aiInsight());
            job.setEvidenceSources(result.evidenceSources());
            job.setCompletedAt(Instant.now());
            job.setUpdatedAt(Instant.now());
            AiAnalysisJob saved = jobs.save(job);
            finalizeProfile(saved);
            jobsCompleted.increment();
            if (job.getStartedAt() != null) {
                long durationMs = java.time.Duration.between(job.getStartedAt(), Instant.now()).toMillis();
                processingDuration.record(durationMs, MILLISECONDS);
            }
            return saved;
        });
    }

    /**
     * Server-side re-validation of the AI insight. Mirrors the rules enforced
     * by the AI service itself (see {@code AiInsightResult}): the narrative
     * must be present, reasonably sized, and must not present itself as a
     * diagnosis. Mongo must never store unrestricted raw LLM output.
     */
    private void validateAiInsight(String aiInsight) {
        if (aiInsight == null || aiInsight.isBlank()) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "AI insight is required and must not be blank.");
        }
        String normalized = aiInsight.trim();
        int length = normalized.length();
        if (length < 20) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "AI insight is too short to be a meaningful wellness narrative.");
        }
        if (length > 4000) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "AI insight exceeds the maximum allowed length.");
        }
        String lowered = normalized.toLowerCase();
        if (lowered.startsWith("diagnos") || DIAGNOSIS_TERMS.stream().anyMatch(lowered::contains)) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "AI insight must not present itself as a diagnosis.");
        }
    }

    private void finalizeProfile(AiAnalysisJob job) {
        DeterministicScores scores = job.getScores();
        if (scores == null) {
            return;
        }
        com.mindease.backend.wellness.application.WellnessAnalysisService.MoodSummary mood = null;
        if (scores.getOnboardingMood() != null && !scores.getOnboardingMood().isBlank()) {
            mood = new com.mindease.backend.wellness.application.WellnessAnalysisService.MoodSummary(
                    scores.getOnboardingMood(),
                    scores.getOnboardingMoodEmotion(),
                    scores.getOnboardingMoodIntensity(),
                    scores.getOnboardingMoodScore(),
                    scores.getMoodTrendDirection() != null ? scores.getMoodTrendDirection() : "unknown",
                    scores.getMoodTrendDescription() != null ? scores.getMoodTrendDescription()
                            : "Not enough mood records to determine a trend.",
                    scores.getMoodHistoryCount() != null ? scores.getMoodHistoryCount() : 0,
                    scores.getCameraEmotion(),
                    scores.getCameraConfidence(),
                    scores.getCameraModelVersion(),
                    scores.getSignalAgreement() != null ? scores.getSignalAgreement() : "noSignal");
        }
        profiles.completeFromJob(
                job.getUserId(),
                job.getAssessmentId(),
                scores.getWellnessScore() == null ? 0 : scores.getWellnessScore(),
                scores.getStressLevel(),
                scores.getLifestyleScore() == null ? 0 : scores.getLifestyleScore(),
                scores.getSleepQuality(),
                scores.getPrimaryFocus(),
                job.getAiInsight(),
                mood);
    }

    /**
     * Marks the job FAILED with an error message (idempotent for PROCESSING).
     *
     * A {@code QUEUED} job is never failed through this path: it means the job
     * was re-enqueued (e.g. by a retry) after a stale worker finished, and
     * failing it would clobber the new processing round and orphan the
     * re-published message. Stale {@code QUEUED} jobs are instead recovered by
     * the {@link AiStaleJobSweeper}, which transitions them directly.
     */
    public AiAnalysisJob fail(String jobId, String error) {
        AiAnalysisJob job = requireInternal(jobId);
        if (job.getStatus() == AiJobStatus.COMPLETED) {
            return job;
        }
        if (job.getStatus() == AiJobStatus.QUEUED) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "Job is not currently being processed.");
        }
        job = markFailed(job, error);
        finalizeDeterministicFallback(job);
        return job;
    }

    /**
     * Marks a wedged job FAILED on behalf of the stale-job sweeper. Unlike
     * {@link #fail(String, String)} this also accepts QUEUED jobs, because the
     * sweeper only reaches a QUEUED job once its publish/claim window elapsed.
     */
    public AiAnalysisJob expire(String jobId, String error) {
        AiAnalysisJob job = requireInternal(jobId);
        if (job.getStatus() == AiJobStatus.COMPLETED) {
            return job;
        }
        job = markFailed(job, error);
        finalizeDeterministicFallback(job);
        log.warn("ai_job_stale_failed jobId={}", jobId);
        return job;
    }

    private AiAnalysisJob markFailed(AiAnalysisJob job, String error) {
        job.setStatus(AiJobStatus.FAILED);
        job.setErrorMessage(error == null || error.isBlank()
                ? "The analysis could not be completed."
                : error.length() > 500 ? error.substring(0, 500) : error);
        job.setUpdatedAt(Instant.now());
        jobsFailed.increment();
        if (job.getStartedAt() != null) {
            long durationMs = java.time.Duration.between(job.getStartedAt(), Instant.now()).toMillis();
            processingDuration.record(durationMs, MILLISECONDS);
        }
        return jobs.save(job);
    }

    /**
     * A terminal AI failure must never strand the user on an "AI pending"
     * profile: the deterministic score and narrative are already a pure
     * function of the stored answers. Publish them so the dashboard stays
     * usable; a later successful retry overwrites the narrative with the
     * AI-generated one through {@link #complete(String, AiAnalysisResultRequest)}.
     */
    private void finalizeDeterministicFallback(AiAnalysisJob job) {
        if (job.getAssessmentId() == null || job.getUserId() == null) {
            return;
        }
        try {
            screenings.findById(job.getAssessmentId())
                    .filter(screening -> job.getUserId().equals(screening.getUserId()))
                    .ifPresent(screening -> {
                        WellnessAnalysisService.Analysis fallback = analysis.analyze(screening);
                        profiles.completeFor(job.getUserId(), job.getAssessmentId(), fallback);
                        log.info("ai_job_deterministic_fallback jobId={} assessmentId={}",
                                job.getId(), job.getAssessmentId());
                    });
        } catch (Exception e) {
            // Never let fallback bookkeeping mask the original job failure.
            log.warn("ai_job_fallback_failed jobId={} error={}", job.getId(), e.getMessage());
        }
    }

    /** Publishes the job id to the AI task queue. Returns false on failure. */
    public boolean publish(String jobId) {
        try {
            byte[] payload = objectMapper.writeValueAsBytes(Map.of("jobId", jobId));
            rabbit.convertAndSend(aiTasksQueue.getName(), payload);
            log.info("ai_job_enqueued jobId={}", jobId);
            return true;
        } catch (AmqpException | com.fasterxml.jackson.core.JsonProcessingException exc) {
            log.warn("ai_job_publish_failed jobId={} error={}", jobId, exc.getMessage());
            publishFailures.increment();
            return false;
        }
    }

    private AiAnalysisJob requireOwned(String userId, String jobId) {
        return jobs.findByIdAndUserId(jobId, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "Analysis job not found."));
    }

    private AiAnalysisJob requireInternal(String jobId) {
        return jobs.findById(jobId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "Analysis job not found."));
    }
}
