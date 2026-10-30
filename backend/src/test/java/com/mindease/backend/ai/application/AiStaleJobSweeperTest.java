package com.mindease.backend.ai.application;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.ai.domain.AiAnalysisJob;
import com.mindease.backend.ai.domain.AiAnalysisJobRepository;
import com.mindease.backend.ai.domain.AiJobStatus;
import com.mindease.backend.config.AppProperties;

/**
 * Verifies a wedged PROCESSING job (consumer died between claim and
 * complete/fail) is swept to FAILED so the owner can retry it instead of the
 * client polling forever. The sweep delegates to the job service so the
 * deterministic fallback profile is published too.
 */
@ExtendWith(MockitoExtension.class)
class AiStaleJobSweeperTest {

    @Mock
    private AiAnalysisJobRepository jobs;

    @Mock
    private AiAnalysisJobService jobService;

    private AiStaleJobSweeper sweeper;
    private AppProperties props;

    @BeforeEach
    void setUp() {
        props = new AppProperties();
        props.getAi().setClaimTimeout(java.time.Duration.ofMinutes(5));
        sweeper = new AiStaleJobSweeper(jobs, jobService, props);
    }

    @Test
    void expiresStaleProcessingJobsThroughTheService() {
        AiAnalysisJob wedged = new AiAnalysisJob();
        wedged.setId("job-1");
        wedged.setStatus(AiJobStatus.PROCESSING);
        wedged.setStartedAt(Instant.now().minus(10, ChronoUnit.MINUTES));
        when(jobs.findByStatusAndStartedAtBefore(eq(AiJobStatus.PROCESSING), any(Instant.class)))
                .thenReturn(List.of(wedged));

        sweeper.sweep();

        verify(jobService).expire(eq("job-1"), contains("timed out"));
    }

    @Test
    void expiresStaleQueuedJobsWhoseMessageWasLost() {
        AiAnalysisJob lost = new AiAnalysisJob();
        lost.setId("job-2");
        lost.setStatus(AiJobStatus.QUEUED);
        lost.setCreatedAt(Instant.now().minus(10, ChronoUnit.MINUTES));
        when(jobs.findByStatusAndStartedAtBefore(eq(AiJobStatus.PROCESSING), any(Instant.class)))
                .thenReturn(List.of());
        when(jobs.findByStatusAndCreatedAtBefore(eq(AiJobStatus.QUEUED), any(Instant.class)))
                .thenReturn(List.of(lost));

        sweeper.sweep();

        verify(jobService).expire(eq("job-2"), anyString());
    }

    @Test
    void leavesRecentProcessingJobsAlone() {
        when(jobs.findByStatusAndStartedAtBefore(eq(AiJobStatus.PROCESSING), any(Instant.class)))
                .thenReturn(List.of());
        when(jobs.findByStatusAndCreatedAtBefore(eq(AiJobStatus.QUEUED), any(Instant.class)))
                .thenReturn(List.of());

        sweeper.sweep();

        verify(jobService, never()).expire(anyString(), anyString());
    }
}
