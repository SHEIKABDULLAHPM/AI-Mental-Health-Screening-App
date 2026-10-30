package com.mindease.backend.features.challenges.application;

import com.mindease.backend.features.challenges.domain.Challenge;

/**
 * Evaluates whether a user is eligible for a challenge based on controlled,
 * explainable signals derived from verified activity.
 *
 * <p>Eligibility rules are single controlled strings. Only known rules are
 * honored; unknown rules default to eligible (they never block a challenge).
 * No clinical assumptions are made here.</p>
 *
 * <p>Supported rule values:</p>
 * <ul>
 *   <li>{@code null} / empty / {@code always} — eligible for everyone.</li>
 *   <li>{@code mood:any} — user has recorded at least one mood.</li>
 *   <li>{@code journal:any} — user has created at least one journal entry.</li>
 *   <li>{@code relax:active} — user has completed at least one relaxation activity.</li>
 *   <li>{@code recommendation:completed} — user has completed a recommendation.</li>
 * </ul>
 */
public final class ChallengeEligibilityEngine {

    private ChallengeEligibilityEngine() {
    }

    /**
     * Whether the user is eligible for the challenge given its eligibility rule
     * and the user's current activity signals.
     */
    public static boolean isEligible(Challenge challenge, EligibilitySignals signals) {
        String rule = challenge.getEligibilityRule();
        if (rule == null || rule.isBlank() || "always".equalsIgnoreCase(rule.trim())) {
            return true;
        }
        return switch (rule.trim().toLowerCase()) {
            case "mood:any" -> signals.moodEntryCount() > 0;
            case "journal:any" -> signals.journalEntryCount() > 0;
            case "relax:active" -> signals.relaxCompletionCount() > 0;
            case "recommendation:completed" -> signals.recommendationCompletedCount() > 0;
            default -> true;
        };
    }

    /**
     * Immutable view of the controlled signals used for eligibility.
     */
    public record EligibilitySignals(
            int moodEntryCount,
            int journalEntryCount,
            int relaxCompletionCount,
            int recommendationCompletedCount) {

        public static EligibilitySignals empty() {
            return new EligibilitySignals(0, 0, 0, 0);
        }
    }
}
