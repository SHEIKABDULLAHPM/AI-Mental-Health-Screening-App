package com.mindease.backend.features.emotion.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** Guards the constants the wire contract and the service both depend on. */
class EmotionClassesTest {

    @Test
    void countMatchesCanonicalSet() {
        assertThat(EmotionClasses.COUNT).isEqualTo(EmotionClasses.CANONICAL.size());
    }

    @Test
    void canonicalSetIsExactlyTheSevenVitClasses() {
        assertThat(EmotionClasses.CANONICAL).containsExactlyInAnyOrder(
                "anger", "disgust", "fear", "happy", "neutral", "sad", "surprise");
    }

    @Test
    void patternCoversEveryCanonicalClassAndUnknown() {
        for (String c : EmotionClasses.CANONICAL) {
            assertThat(EmotionClasses.PATTERN).contains(c);
        }
        assertThat(EmotionClasses.PATTERN).contains(EmotionClasses.UNKNOWN);
    }

    @Test
    void removedSynoraClassesAreGone() {
        // The 8-class vocabulary must not reappear: the ViT cannot emit them.
        assertThat(EmotionClasses.PATTERN).doesNotContain("contempt");
        assertThat(EmotionClasses.PATTERN).doesNotContain("happiness");
        assertThat(EmotionClasses.PATTERN).doesNotContain("sadness");
    }
}
