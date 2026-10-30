package com.mindease.backend.wellness.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;

import com.mindease.backend.screening.domain.MoodAssessment;

/**
 * Unit tests for the deterministic camera-vs-self-report verdict and the
 * onboarding mood summary carrying the camera supporting signal.
 * The verdict mirrors the Flutter {@code cameraAgreement()} tables, so both
 * layers display the same relationship for the same inputs.
 */
class WellnessAnalysisServiceTest {

    private final WellnessAnalysisService service = new WellnessAnalysisService();

    private static MoodAssessment mood(String currentMood) {
        MoodAssessment m = new MoodAssessment();
        m.setCurrentMood(currentMood);
        return m;
    }

    private static Map<String, Object> trend() {
        return Map.of("direction", "stable",
                "description", "Your mood has been fairly consistent recently.",
                "dataPoints", 4);
    }

    // ── canonical mapping ──

    @Test
    void mapCanonicalToMoodCoversAllSevenClasses() {
        assertThat(WellnessAnalysisService.mapCanonicalToMood("happy")).isEqualTo("happy");
        assertThat(WellnessAnalysisService.mapCanonicalToMood("neutral")).isEqualTo("calm");
        assertThat(WellnessAnalysisService.mapCanonicalToMood("sad")).isEqualTo("low");
        assertThat(WellnessAnalysisService.mapCanonicalToMood("anger")).isEqualTo("stressed");
        assertThat(WellnessAnalysisService.mapCanonicalToMood("fear")).isEqualTo("stressed");
        assertThat(WellnessAnalysisService.mapCanonicalToMood("surprise")).isEqualTo("okay");
        assertThat(WellnessAnalysisService.mapCanonicalToMood("disgust")).isEqualTo("low");
    }

    @Test
    void mapCanonicalToMoodRejectsUnknown() {
        assertThat(WellnessAnalysisService.mapCanonicalToMood("unknown")).isNull();
        assertThat(WellnessAnalysisService.mapCanonicalToMood("contempt")).isNull();
        assertThat(WellnessAnalysisService.mapCanonicalToMood(null)).isNull();
    }

    // ── agreement verdict ──

    @Test
    void agreementWhenCameraMatchesSelfReport() {
        assertThat(WellnessAnalysisService.cameraAgreement("happy", "happy", 0.85))
                .isEqualTo("agree");
        assertThat(WellnessAnalysisService.cameraAgreement("calm", "neutral", 0.9))
                .isEqualTo("agree");
        assertThat(WellnessAnalysisService.cameraAgreement("stressed", "anger", 0.75))
                .isEqualTo("agree");
    }

    @Test
    void disagreementIsLabeledWithoutOverriding() {
        // Happy self-report vs sad camera: verdict differs; the mood itself
        // is untouched (asserted in the summary test below).
        assertThat(WellnessAnalysisService.cameraAgreement("happy", "sad", 0.55))
                .isEqualTo("differs");
    }

    @Test
    void adjacentMoodsAreClose() {
        assertThat(WellnessAnalysisService.cameraAgreement("okay", "neutral", 0.8))
                .isEqualTo("close");
    }

    @Test
    void lowConfidenceUnknownOrAbsentCameraYieldsNoSignal() {
        assertThat(WellnessAnalysisService.cameraAgreement("happy", "sad", 0.2))
                .isEqualTo("noSignal");
        assertThat(WellnessAnalysisService.cameraAgreement("happy", "sad", 0.29))
                .isEqualTo("noSignal");
        assertThat(WellnessAnalysisService.cameraAgreement("low", "unknown", 0.9))
                .isEqualTo("noSignal");
        assertThat(WellnessAnalysisService.cameraAgreement("low", null, 0.9))
                .isEqualTo("noSignal");
        assertThat(WellnessAnalysisService.cameraAgreement("low", "sad", null))
                .isEqualTo("noSignal");
    }

    // ── summary carrying ──

    @Test
    void moodSummaryCarriesCameraSignalAndPreservesSelfReport() {
        WellnessAnalysisService.CameraSignal camera =
                new WellnessAnalysisService.CameraSignal("sad", 0.55, "vit-fer-7");
        WellnessAnalysisService.MoodSummary summary =
                service.moodSummary(mood("happy"), trend(), 5, camera);

        assertThat(summary.mood()).isEqualTo("happy");
        assertThat(summary.moodScore())
                .isEqualTo(com.mindease.backend.features.mood.application.MoodTrendAnalyzer
                        .moodToValue("happy"));
        assertThat(summary.cameraEmotion()).isEqualTo("sad");
        assertThat(summary.cameraConfidence()).isEqualTo(0.55);
        assertThat(summary.cameraModelVersion()).isEqualTo("vit-fer-7");
        assertThat(summary.signalAgreement()).isEqualTo("differs");
    }

    @Test
    void moodSummaryWithoutCameraDegradesToNoSignal() {
        WellnessAnalysisService.MoodSummary summary =
                service.moodSummary(mood("calm"), trend(), 0, null);

        assertThat(summary.mood()).isEqualTo("calm");
        assertThat(summary.cameraEmotion()).isNull();
        assertThat(summary.cameraConfidence()).isNull();
        assertThat(summary.signalAgreement()).isEqualTo("noSignal");
    }

    @Test
    void moodSummaryWithoutMoodReturnsNull() {
        assertThat(service.moodSummary(null, trend(), 3, null)).isNull();
        assertThat(service.moodSummary(mood("  "), trend(), 3, null)).isNull();
    }
}
