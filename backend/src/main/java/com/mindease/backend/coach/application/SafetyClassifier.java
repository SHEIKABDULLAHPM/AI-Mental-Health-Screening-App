package com.mindease.backend.coach.application;

import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Client-side safety classification for incoming user messages.
 * Uses keyword/pattern detection as first line of defense.
 * The AI service can provide additional server-side classification.
 */
@Component
public class SafetyClassifier {

    private static final Logger log = LoggerFactory.getLogger(SafetyClassifier.class);

    private static final Set<String> IMMEDIATE_DANGER_KEYWORDS = Set.of(
            "kill myself", "end my life", "suicide", "suicidal",
            "want to die", "going to die", "end it all",
            "hang myself", "overdose", "jump off",
            "cut my wrists", " slit my wrists", "no reason to live");

    private static final Set<String> HIGH_RISK_KEYWORDS = Set.of(
            "self harm", "self-harm", "hurt myself", "harm myself",
            "cut myself", "burn myself", "starve myself",
            "drink too much", "pills", "not worth living",
            "better off dead", "nobody would care",
            "can't go on", "can't take it anymore");

    private static final Set<String> CONCERNING_KEYWORDS = Set.of(
            "hopeless", "worthless", "helpless", "trapped",
            "no way out", "give up", "give up on life",
            "tired of living", "exhausted with life",
            "don't want to be here", "disappear", "vanish",
            "numb inside", "empty inside", "lost all hope");

    /**
     * Classify a user message into a safety state.
     * Returns one of: NORMAL, CONCERNING, HIGH_RISK, IMMEDIATE_DANGER
     *
     * The safety classifier fails closed: if unsure, it errs on the side
     * of more concern, not less.
     */
    public String classify(String message) {
        if (message == null || message.isBlank()) {
            return "NORMAL";
        }

        String lower = message.toLowerCase().trim();

        // Check most severe first
        for (String keyword : IMMEDIATE_DANGER_KEYWORDS) {
            if (lower.contains(keyword)) {
                log.warn("safety_immediate_danger detected keyword='{}'", keyword);
                return "IMMEDIATE_DANGER";
            }
        }

        for (String keyword : HIGH_RISK_KEYWORDS) {
            if (lower.contains(keyword)) {
                log.warn("safety_high_risk detected keyword='{}'", keyword);
                return "HIGH_RISK";
            }
        }

        for (String keyword : CONCERNING_KEYWORDS) {
            if (lower.contains(keyword)) {
                log.info("safety_concerning detected keyword='{}'", keyword);
                return "CONCERNING";
            }
        }

        return "NORMAL";
    }

    /**
     * Check if a safety state requires special handling (not normal conversation).
     */
    public boolean requiresSpecialHandling(String safetyState) {
        return "HIGH_RISK".equals(safetyState) || "IMMEDIATE_DANGER".equals(safetyState);
    }
}
