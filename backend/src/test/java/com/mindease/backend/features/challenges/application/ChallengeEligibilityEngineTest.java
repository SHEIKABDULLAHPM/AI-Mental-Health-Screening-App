package com.mindease.backend.features.challenges.application;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

import com.mindease.backend.features.challenges.application.ChallengeEligibilityEngine.EligibilitySignals;
import com.mindease.backend.features.challenges.domain.Challenge;

class ChallengeEligibilityEngineTest {

    @Test
    void defaultRuleEligibleForEveryone() {
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge(null), EligibilitySignals.empty())).isTrue();
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge(""), EligibilitySignals.empty())).isTrue();
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("always"), EligibilitySignals.empty())).isTrue();
    }

    @Test
    void moodRuleRequiresMoodActivity() {
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("mood:any"), EligibilitySignals.empty())).isFalse();
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("mood:any"), new EligibilitySignals(1, 0, 0, 0))).isTrue();
    }

    @Test
    void journalRuleRequiresJournalActivity() {
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("journal:any"), EligibilitySignals.empty())).isFalse();
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("journal:any"), new EligibilitySignals(0, 2, 0, 0))).isTrue();
    }

    @Test
    void relaxRuleRequiresRelaxActivity() {
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("relax:active"), EligibilitySignals.empty())).isFalse();
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("relax:active"), new EligibilitySignals(0, 0, 3, 0))).isTrue();
    }

    @Test
    void unknownRuleDefaultsToEligible() {
        assertThat(ChallengeEligibilityEngine.isEligible(
                challenge("some:unknown:rule"), EligibilitySignals.empty())).isTrue();
    }

    private static Challenge challenge(String rule) {
        Challenge c = new Challenge();
        c.setEligibilityRule(rule);
        return c;
    }
}
