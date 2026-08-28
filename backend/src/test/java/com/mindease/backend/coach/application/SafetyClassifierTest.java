package com.mindease.backend.coach.application;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class SafetyClassifierTest {

    private SafetyClassifier classifier;

    @BeforeEach
    void setUp() {
        classifier = new SafetyClassifier();
    }

    @Test
    void normalMessage_classifiedAsNormal() {
        assertThat(classifier.classify("I had a good day today")).isEqualTo("NORMAL");
    }

    @Test
    void nullMessage_classifiedAsNormal() {
        assertThat(classifier.classify(null)).isEqualTo("NORMAL");
    }

    @Test
    void emptyMessage_classifiedAsNormal() {
        assertThat(classifier.classify("")).isEqualTo("NORMAL");
        assertThat(classifier.classify("  ")).isEqualTo("NORMAL");
    }

    @Test
    void concerningKeywords_classifiedAsConcerning() {
        assertThat(classifier.classify("I feel hopeless")).isEqualTo("CONCERNING");
        assertThat(classifier.classify("I feel worthless")).isEqualTo("CONCERNING");
        assertThat(classifier.classify("I feel trapped")).isEqualTo("CONCERNING");
        assertThat(classifier.classify("I want to give up on life")).isEqualTo("CONCERNING");
    }

    @Test
    void highRiskKeywords_classifiedAsHighRisk() {
        assertThat(classifier.classify("I want to hurt myself")).isEqualTo("HIGH_RISK");
        assertThat(classifier.classify("I want to self harm")).isEqualTo("HIGH_RISK");
        assertThat(classifier.classify("I can't take it anymore")).isEqualTo("HIGH_RISK");
    }

    @Test
    void immediateDangerKeywords_classifiedAsImmediateDanger() {
        assertThat(classifier.classify("I want to kill myself")).isEqualTo("IMMEDIATE_DANGER");
        assertThat(classifier.classify("I want to end my life")).isEqualTo("IMMEDIATE_DANGER");
        assertThat(classifier.classify("I am suicidal")).isEqualTo("IMMEDIATE_DANGER");
        assertThat(classifier.classify("I want to die")).isEqualTo("IMMEDIATE_DANGER");
    }

    @Test
    void severityOrder_precedesOverConcerning() {
        // "hurt myself" (high risk) should take precedence over "hopeless" (concerning)
        assertThat(classifier.classify("I feel hopeless and want to hurt myself"))
                .isEqualTo("HIGH_RISK");
    }

    @Test
    void immediateDanger_precedesHighRisk() {
        // "kill myself" (immediate danger) should take precedence over "hurt myself" (high risk)
        assertThat(classifier.classify("I want to hurt myself and kill myself"))
                .isEqualTo("IMMEDIATE_DANGER");
    }

    @Test
    void requiresSpecialHandling_forHighRisk() {
        assertThat(classifier.requiresSpecialHandling("HIGH_RISK")).isTrue();
        assertThat(classifier.requiresSpecialHandling("IMMEDIATE_DANGER")).isTrue();
    }

    @Test
    void requiresSpecialHandling_forNormalAndConcerning() {
        assertThat(classifier.requiresSpecialHandling("NORMAL")).isFalse();
        assertThat(classifier.requiresSpecialHandling("CONCERNING")).isFalse();
    }

    @Test
    void caseInsensitive() {
        assertThat(classifier.classify("I WANT TO KILL MYSELF")).isEqualTo("IMMEDIATE_DANGER");
        assertThat(classifier.classify("I Feel Hopeless")).isEqualTo("CONCERNING");
    }
}
