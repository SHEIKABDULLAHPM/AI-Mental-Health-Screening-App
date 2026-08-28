package com.mindease.backend.ai.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
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
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.core.RabbitTemplate;

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
import com.mindease.backend.wellness.application.WellnessProfileService;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

/**
 * Unit tests for the AI job lifecycle: claim / complete / fail / retry,
 * ownership scoping and the server-side AI-result validation.
 */
@ExtendWith(MockitoExtension.class)
class AiAnalysisJobServiceTest {

    @Mock
    private AiAnalysisJobRepository jobs;

    @Mock
    private RabbitTemplate rabbit;

    @Mock
    private WellnessProfileService profiles;

    private AiAnalysisJobService service;
    private Queue queue;
    private AppProperties props;

    private static final String OWNER = "user-1";
    private static final String JOB_ID = "job-1";

    @BeforeEach
    void setUp() {
        props = new AppProperties();
        props.getAi().setMaxAttempts(3);
        props.getAi().setTasksQueue("ai_tasks");
        queue = new Queue("ai_tasks", true);
        MeterRegistry meterRegistry = new SimpleMeterRegistry();
        service = new AiAnalysisJobService(
                jobs, rabbit, queue, props, new ObjectMapper(), profiles, meterRegistry);
    }

    // ------------------------------------------------------------------ create

    @Test
    void createPublishesQueuedJob() {
        AiAnalysisJob saved = job(AiJobStatus.QUEUED, 0);
        when(jobs.save(any())).thenReturn(saved);

        AiAnalysisJob created = service.create(OWNER, "assessment-1", scores());

        assertThat(created.getStatus()).isEqualTo(AiJobStatus.QUEUED);
        assertThat(created.getAttemptCount()).isZero();
        verify(rabbit).convertAndSend(eq("ai_tasks"), any(byte[].class));
    }

    @Test
    void createMarksFailedWhenPublishFails() {
        AiAnalysisJob saved = job(AiJobStatus.QUEUED, 0);
        when(jobs.save(any())).thenReturn(saved);
        doThrow(amqpFailure()).when(rabbit).convertAndSend(anyString(), any(byte[].class));

        AiAnalysisJob created = service.create(OWNER, "assessment-1", scores());

        assertThat(created.getStatus()).isEqualTo(AiJobStatus.FAILED);
        assertThat(created.getErrorMessage()).contains("enqueued");
    }

    // ------------------------------------------------------------------ claim

    @Test
    void claimTransitionsQueuedToProcessingAndBumpsAttempt() {
        AiAnalysisJob queued = job(AiJobStatus.QUEUED, 0);
        queued.setScores(scores());
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(queued));

        DeterministicScores claimed = service.claim(JOB_ID);

        assertThat(queued.getStatus()).isEqualTo(AiJobStatus.PROCESSING);
        assertThat(queued.getAttemptCount()).isEqualTo(1);
        assertThat(queued.getStartedAt()).isNotNull();
        assertThat(claimed.getPrimaryFocus()).isEqualTo("STRESS_MANAGEMENT");
    }

    @Test
    void claimDoesNotDoubleBumpAlreadyProcessingJob() {
        AiAnalysisJob processing = job(AiJobStatus.PROCESSING, 2);
        processing.setScores(scores());
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(processing));

        service.claim(JOB_ID);

        assertThat(processing.getAttemptCount()).isEqualTo(2);
        verify(jobs, never()).save(any());
    }

    @Test
    void claimRejectsCompletedJob() {
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job(AiJobStatus.COMPLETED, 1)));

        assertThatThrownBy(() -> service.claim(JOB_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    // ----------------------------------------------------------------- complete

    @Test
    void completeStoresInsightAndFinalizesProfile() {
        AiAnalysisJob processing = job(AiJobStatus.PROCESSING, 1);
        processing.setScores(scores());
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(processing));
        when(jobs.save(any())).thenReturn(processing);

        AiAnalysisJob completed = service.complete(JOB_ID, validResult());

        assertThat(completed.getStatus()).isEqualTo(AiJobStatus.COMPLETED);
        assertThat(completed.getAiInsight()).isEqualTo(VALID_INSIGHT);
        assertThat(completed.getCompletedAt()).isNotNull();
        verify(profiles).completeFromJob(eq(OWNER), eq("assessment-1"), anyInt(), eq("HIGH"),
                anyInt(), eq("FAIR"), eq("STRESS_MANAGEMENT"), eq(VALID_INSIGHT));
    }

    @Test
    void completeIsIdempotentWhenAlreadyCompleted() {
        AiAnalysisJob completed = job(AiJobStatus.COMPLETED, 1);
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(completed));

        AiAnalysisJob result = service.complete(JOB_ID, validResult());

        assertThat(result).isSameAs(completed);
        verify(jobs, never()).save(any());
    }

    @Test
    void completeRejectsBlankInsight() {
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job(AiJobStatus.PROCESSING, 1)));

        assertValidationFailure(() ->
                service.complete(JOB_ID, new AiAnalysisResultRequest("   ", null)),
                "must not be blank");
    }

    @Test
    void completeRejectsTooShortInsight() {
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job(AiJobStatus.PROCESSING, 1)));

        assertValidationFailure(() ->
                service.complete(JOB_ID, new AiAnalysisResultRequest("Hi.", null)),
                "too short");
    }

    @Test
    void completeRejectsTooLongInsight() {
        String longInsight = "a".repeat(4001);
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job(AiJobStatus.PROCESSING, 1)));

        assertValidationFailure(() ->
                service.complete(JOB_ID, new AiAnalysisResultRequest(longInsight, null)),
                "maximum allowed length");
    }

    @Test
    void completeRejectsDiagnosisWording() {
        String diagnosis = "You are suffering from clinical depression.";
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job(AiJobStatus.PROCESSING, 1)));

        assertValidationFailure(() ->
                service.complete(JOB_ID, new AiAnalysisResultRequest(diagnosis, null)),
                "must not present itself as a diagnosis");
    }

    @Test
    void completeRejectsJobNotBeingProcessed() {
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job(AiJobStatus.QUEUED, 0)));

        assertThatThrownBy(() -> service.complete(JOB_ID, validResult()))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    // ------------------------------------------------------------------ fail

    @Test
    void failMarksJobFailedAndTruncatesError() {
        AiAnalysisJob processing = job(AiJobStatus.PROCESSING, 1);
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(processing));
        when(jobs.save(any())).thenReturn(processing);

        AiAnalysisJob failed = service.fail(JOB_ID, "x".repeat(900));

        assertThat(failed.getStatus()).isEqualTo(AiJobStatus.FAILED);
        assertThat(failed.getErrorMessage()).hasSize(500);
    }

    @Test
    void failRejectsQueuedJobSoRetriedRoundIsNotClobbered() {
        AiAnalysisJob queued = job(AiJobStatus.QUEUED, 1);
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(queued));

        assertConflict(() -> service.fail(JOB_ID, "stale worker"));
        verify(jobs, never()).save(any());
    }

    @Test
    void failIsIdempotentWhenAlreadyCompleted() {
        AiAnalysisJob completed = job(AiJobStatus.COMPLETED, 1);
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(completed));

        AiAnalysisJob result = service.fail(JOB_ID, "boom");

        assertThat(result.getStatus()).isEqualTo(AiJobStatus.COMPLETED);
        verify(jobs, never()).save(any());
    }

    // ------------------------------------------------------------------ retry

    @Test
    void retryRequeuesFailedJob() {
        AiAnalysisJob failed = failed();
        when(jobs.findByIdAndUserId(JOB_ID, OWNER)).thenReturn(Optional.of(failed));

        AiAnalysisJobDto dto = service.retry(OWNER, JOB_ID);

        assertThat(dto.status()).isEqualTo(AiJobStatus.QUEUED);
        assertThat(dto.errorMessage()).isNull();
        verify(rabbit).convertAndSend(eq("ai_tasks"), any(byte[].class));
    }

    @Test
    void retryRejectsCompletedJob() {
        when(jobs.findByIdAndUserId(JOB_ID, OWNER))
                .thenReturn(Optional.of(job(AiJobStatus.COMPLETED, 1)));

        assertConflict(() -> service.retry(OWNER, JOB_ID));
    }

    @Test
    void retryRejectsProcessingJob() {
        when(jobs.findByIdAndUserId(JOB_ID, OWNER))
                .thenReturn(Optional.of(job(AiJobStatus.PROCESSING, 1)));

        assertConflict(() -> service.retry(OWNER, JOB_ID));
    }

    @Test
    void retryRejectsWhenMaxAttemptsReached() {
        when(jobs.findByIdAndUserId(JOB_ID, OWNER))
                .thenReturn(Optional.of(job(AiJobStatus.FAILED, 3)));

        assertConflict(() -> service.retry(OWNER, JOB_ID));
    }

    @Test
    void retryRevertsToFailedWhenPublishFails() {
        AiAnalysisJob failed = failed();
        when(jobs.findByIdAndUserId(JOB_ID, OWNER)).thenReturn(Optional.of(failed));
        doThrow(amqpFailure()).when(rabbit).convertAndSend(anyString(), any(byte[].class));

        assertThatThrownBy(() -> service.retry(OWNER, JOB_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.UPSTREAM_UNAVAILABLE);
        assertThat(failed.getStatus()).isEqualTo(AiJobStatus.FAILED);
    }

    // ------------------------------------------------------- ownership scoping

    @Test
    void statusForRejectsForeignUser() {
        when(jobs.findByIdAndUserId(JOB_ID, "other-user")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.statusFor("other-user", JOB_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void statusForReturnsOwnerJob() {
        AiAnalysisJob job = job(AiJobStatus.PROCESSING, 1);
        when(jobs.findByIdAndUserId(JOB_ID, OWNER)).thenReturn(Optional.of(job));

        AiAnalysisJobDto dto = service.statusFor(OWNER, JOB_ID);

        assertThat(dto.jobId()).isEqualTo(JOB_ID);
        assertThat(dto.status()).isEqualTo(AiJobStatus.PROCESSING);
    }

    // ------------------------------------------------------------------ utils

    private static final String VALID_INSIGHT =
            "You have been managing a lot lately, and that is okay. Small daily breaks "
                    + "can help you feel grounded and in control.";

    private static AiAnalysisResultRequest validResult() {
        return new AiAnalysisResultRequest(VALID_INSIGHT,
                List.of("WHO-Psychological-Self-Help"));
    }

    private static DeterministicScores scores() {
        DeterministicScores s = new DeterministicScores();
        s.setPhq9(15);
        s.setGad7(12);
        s.setPss10(17);
        s.setWho5(11);
        s.setWellnessScore(42);
        s.setStressLevel("HIGH");
        s.setLifestyleScore(55);
        s.setSleepQuality("FAIR");
        s.setPrimaryFocus("STRESS_MANAGEMENT");
        return s;
    }

    private static AiAnalysisJob failed() {
        AiAnalysisJob j = job(AiJobStatus.FAILED, 1);
        j.setErrorMessage("boom");
        return j;
    }

    private static AiAnalysisJob job(AiJobStatus status, int attempts) {
        AiAnalysisJob j = new AiAnalysisJob();
        j.setId(JOB_ID);
        j.setUserId(OWNER);
        j.setAssessmentId("assessment-1");
        j.setStatus(status);
        j.setAttemptCount(attempts);
        j.setMaxAttempts(3);
        j.setCreatedAt(Instant.now());
        j.setUpdatedAt(Instant.now());
        return j;
    }

    private static AmqpException amqpFailure() {
        return new AmqpException("broker down") {
        };
    }

    private void assertValidationFailure(
            org.assertj.core.api.ThrowableAssert.ThrowingCallable callable,
            String messageFragment) {
        assertThatThrownBy(callable)
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.VALIDATION_FAILED);
                    assertThat(((ApiException) ex).getMessage()).contains(messageFragment);
                });
    }

    private void assertConflict(org.assertj.core.api.ThrowableAssert.ThrowingCallable callable) {
        assertThatThrownBy(callable)
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void retryRejectsWhenMaxAttemptsExhausted() {
        AiAnalysisJob failed = failed();
        failed.setAttemptCount(3); // maxAttempts = 3
        when(jobs.findByIdAndUserId(JOB_ID, OWNER)).thenReturn(Optional.of(failed));

        assertConflict(() -> service.retry(OWNER, JOB_ID));
    }

    @Test
    void completeIncrementsMetricsOnSuccess() {
        AiAnalysisJob processing = job(AiJobStatus.PROCESSING, 1);
        processing.setScores(scores());
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(processing));
        when(jobs.save(any())).thenReturn(processing);

        service.complete(JOB_ID, validResult());

        verify(jobs).save(any());
    }

    @Test
    void failIncrementsMetricsOnFailure() {
        AiAnalysisJob processing = job(AiJobStatus.PROCESSING, 1);
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(processing));
        when(jobs.save(any())).thenReturn(processing);

        service.fail(JOB_ID, "LLM timeout");

        verify(jobs).save(any());
    }

    @Test
    void publishFailureIncrementsMetrics() {
        AiAnalysisJob saved = job(AiJobStatus.QUEUED, 0);
        when(jobs.save(any())).thenReturn(saved);
        doThrow(amqpFailure()).when(rabbit).convertAndSend(anyString(), any(byte[].class));

        AiAnalysisJob created = service.create(OWNER, "assessment-1", scores());

        assertThat(created.getStatus()).isEqualTo(AiJobStatus.FAILED);
    }

    @Test
    void crossUserIsolationPreventsAccessToOtherUsersJob() {
        when(jobs.findByIdAndUserId(JOB_ID, "other-user")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.statusFor("other-user", JOB_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void internalCallbackCompletesJobWithoutOwnershipCheck() {
        AiAnalysisJob job = job(AiJobStatus.PROCESSING, 1);
        job.setScores(scores());
        when(jobs.findById(JOB_ID)).thenReturn(Optional.of(job));
        when(jobs.save(any())).thenReturn(job);

        // Internal callback (via filter) can complete any job by ID without ownership check
        AiAnalysisJob completed = service.complete(JOB_ID, validResult());
        assertThat(completed.getStatus()).isEqualTo(AiJobStatus.COMPLETED);
    }
}