package com.mindease.backend.ai.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
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
 * client polling forever.
 */
@ExtendWith(MockitoExtension.class)
class AiStaleJobSweeperTest {

    @Mock
    private AiAnalysisJobRepository jobs;

    private AiStaleJobSweeper sweeper;
    private AppProperties props;

    @BeforeEach
    void setUp() {
        props = new AppProperties();
        props.getAi().setClaimTimeout(java.time.Duration.ofMinutes(5));
        sweeper = new AiStaleJobSweeper(jobs, props);
    }

    @Test
    void marksStaleProcessingJobsFailed() {
        AiAnalysisJob wedged = new AiAnalysisJob();
        wedged.setId("job-1");
        wedged.setStatus(AiJobStatus.PROCESSING);
        wedged.setStartedAt(Instant.now().minus(10, ChronoUnit.MINUTES));
        when(jobs.findByStatusAndStartedAtBefore(eq(AiJobStatus.PROCESSING), any(Instant.class)))
                .thenReturn(List.of(wedged));

        sweeper.sweep();

        assertThat(wedged.getStatus()).isEqualTo(AiJobStatus.FAILED);
        assertThat(wedged.getErrorMessage()).contains("timed out");
        verify(jobs).save(wedged);
    }

    @Test
    void leavesRecentProcessingJobsAlone() {
        when(jobs.findByStatusAndStartedAtBefore(eq(AiJobStatus.PROCESSING), any(Instant.class)))
                .thenReturn(List.of());

        sweeper.sweep();

        verify(jobs, never()).save(any());
    }
}