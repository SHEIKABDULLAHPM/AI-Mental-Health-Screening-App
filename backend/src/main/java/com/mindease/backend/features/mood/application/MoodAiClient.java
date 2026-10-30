package com.mindease.backend.features.mood.application;

import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.features.mood.dto.AnalyzeMoodRequest;
import com.mindease.backend.features.mood.dto.AnalyzeMoodResponse;

/**
 * Calls the Python AI service at :8000/api/v1/mood/*.
 * AI failure must never break manual mood tracking - callers receive a fallback.
 */
@Component
public class MoodAiClient {

    private static final Logger log = LoggerFactory.getLogger(MoodAiClient.class);

    private final RestTemplate restTemplate;
    private final String aiBaseUrl;
    private final String internalApiKey;

    public MoodAiClient(
            RestTemplate restTemplate,
            @Value("${mindease.ai.service-url:http://ai-service:8000/api/v1}") String aiBaseUrl,
            @Value("${mindease.ai.internal-api-key:}") String internalApiKey) {
        this.restTemplate = restTemplate;
        this.aiBaseUrl = aiBaseUrl;
        this.internalApiKey = internalApiKey;
    }

    public AnalyzeMoodResponse analyzeMood(AnalyzeMoodRequest request) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (internalApiKey != null && !internalApiKey.isBlank()) {
                headers.set("X-Internal-API-Key", internalApiKey);
            }

            var body = new java.util.LinkedHashMap<String, Object>();
            body.put("manual_mood", request.mood());
            body.put("manual_emotion", request.emotion());

            if (request.note() != null && !request.note().isBlank()) {
                body.put("text_observation", Map.of("text", request.note()));
            }

            if (request.cameraObservation() != null) {
                var cam = request.cameraObservation();
                var cameraMap = new java.util.LinkedHashMap<String, Object>();
                cameraMap.put("dominant_emotion", cam.dominantEmotion());
                cameraMap.put("emotion_scores", cam.emotionScores() != null ? cam.emotionScores() : Map.of());
                cameraMap.put("face_detected", cam.faceDetected() != null ? cam.faceDetected() : true);
                cameraMap.put("face_count", cam.faceCount() != null ? cam.faceCount() : 1);
                cameraMap.put("face_quality", cam.faceQuality() != null ? cam.faceQuality() : 0.8);
                cameraMap.put("valence", cam.valence() != null ? cam.valence() : 0.0);
                cameraMap.put("arousal", cam.arousal() != null ? cam.arousal() : 0.0);
                cameraMap.put("frames_analyzed", cam.framesAnalyzed() != null ? cam.framesAnalyzed() : 1);
                cameraMap.put("status", cam.status() != null ? cam.status() : "PREDICTED");
                if (cam.calibratedConfidence() != null) {
                    cameraMap.put("calibrated_confidence", cam.calibratedConfidence());
                }
                cameraMap.put("model_version",
                        cam.modelVersion() != null && !cam.modelVersion().isBlank()
                                ? cam.modelVersion() : "unknown");
                body.put("camera_observation", cameraMap);
            }

            HttpEntity<?> entity = new HttpEntity<>(body, headers);
            String url = aiBaseUrl + "/mood/analyze";

            log.info("Calling AI service: {}", url);
            var response = restTemplate.postForEntity(url, entity, AnalyzeMoodResponse.class);

            if (response.getBody() != null) {
                log.info("AI service returned fusedMood={}", response.getBody().fusedMood());
                return response.getBody();
            }
        } catch (Exception e) {
            log.warn("AI service unavailable, falling back to manual: {}", e.getMessage());
        }

        // Fallback: manual-only result with default guidance
        return new AnalyzeMoodResponse(
                request.mood(),
                null,
                request.emotion() != null ? request.emotion() : "neutral",
                0.0,
                List.of("MANUAL"),
                request.mood(),
                null,
                null,
                false,
                "unavailable",
                new AnalyzeMoodResponse.TrendResult("unknown",
                        "Not enough data for a trend assessment.", 0),
                new AnalyzeMoodResponse.GuidanceResult(
                        "Thank you for checking in. Take a moment to reflect on how you feel.",
                        List.of(
                                Map.of("type", "reflection", "title", "Quick reflection",
                                        "description", "Notice how you are feeling right now.")),
                        false),
                new AnalyzeMoodResponse.SafetyResult(false, "none", null, null),
                new AnalyzeMoodResponse.ReflectionResult(
                        "What affected your mood today?",
                        request.mood(),
                        "reflection"));
    }
}
