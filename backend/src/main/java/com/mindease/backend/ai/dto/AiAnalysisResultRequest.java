package com.mindease.backend.ai.dto;

import java.util.List;

/**
 * Structured result posted back by the AI service on job completion.
 * The deterministic scores and primary focus are authoritative (computed by
 * the backend) - the AI service only contributes the insight narrative and
 * the evidence sources used to ground it.
 */
public record AiAnalysisResultRequest(
        String aiInsight,
        List<String> evidenceSources) {

    public AiAnalysisResultRequest {
        evidenceSources = evidenceSources == null ? List.of() : evidenceSources;
    }
}
