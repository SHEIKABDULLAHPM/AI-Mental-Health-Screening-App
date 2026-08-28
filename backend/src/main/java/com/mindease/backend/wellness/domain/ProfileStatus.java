package com.mindease.backend.wellness.domain;

/**
 * AI analysis state of the wellness profile. AI is deliberately paused for now:
 * every new profile is created with status {@code AI_ANALYSIS_PENDING} and the
 * AI-derived fields stay null until a future AI service consumes the completed
 * assessment.
 */
public enum ProfileStatus {
    AI_ANALYSIS_PENDING,
    COMPLETED
}