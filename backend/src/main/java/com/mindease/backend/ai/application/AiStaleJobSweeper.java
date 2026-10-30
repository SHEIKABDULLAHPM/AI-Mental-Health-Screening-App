package com.mindease.backend.ai.application;

import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import com.mindease.backend.ai.domain.AiAnalysisJob;
import com.mindease.backend.ai.domain.AiAnalysisJobRepository;
import com.mindease.backend.ai.domain.AiJobStatus;
import com.mindease.backend.config.AppProperties;

/**
 * Recovers jobs that wedged in {@code PROCESSING} or were queued but whose
 * message was lost (e.g. the consumer died between publish and claim): if the
 * AI-service consumer dies between {@code claim} and {@code complete}/{@code
 * fail} there is no server-side requeue, so the owner's screen would poll
 * forever. This sweeper marks any {@code PROCESSING} job older than the
 * configured claim timeout - and any {@code QUEUED} job that never started
 * within that window - as {@code FAILED}, letting the owner retry it through
 * the normal flow.
 */
@Component
public class AiStaleJobSweeper {

    private static final Logger log = LoggerFactory.getLogger(AiStaleJobSweeper.class);

    private final AiAnalysisJobRepository jobs;
    private final AiAnalysisJobService jobService;
    private final AppProperties props;

    public AiStaleJobSweeper(AiAnalysisJobRepository jobs,
                             AiAnalysisJobService jobService,
                             AppProperties props) {
        this.jobs = jobs;
        this.jobService = jobService;
        this.props = props;
    }

    @Scheduled(fixedDelayString = "${mindease.ai.stale-sweep-interval:60000}")
    public void sweep() {
        Instant deadline = Instant.now().minus(props.getAi().getClaimTimeout());
        java.util.List<AiAnalysisJob> stale = new java.util.ArrayList<>(jobs.findByStatusAndStartedAtBefore(
                AiJobStatus.PROCESSING, deadline));
        stale.addAll(jobs.findByStatusAndCreatedAtBefore(AiJobStatus.QUEUED, deadline));
        for (AiAnalysisJob job : stale) {
            // Route through the service so a swept job also publishes the
            // deterministic fallback profile instead of stranding the user on
            // an indefinite "AI pending" screen.
            jobService.expire(job.getId(),
                    "Analysis timed out while being processed; please retry.");
        }
        if (!stale.isEmpty()) {
            log.info("ai_stale_sweep_failed_count={}", stale.size());
        }
    }
}