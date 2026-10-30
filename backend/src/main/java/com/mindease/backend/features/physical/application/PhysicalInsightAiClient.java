package com.mindease.backend.features.physical.application;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.features.physical.dto.InsightDtos;

/**
 * Optional AI phrasing for Mind–Body insights.
 *
 * <p>The structured patterns are produced deterministically by
 * {@link MindBodyPatternEngine}; this client only asks the AI service for
 * supportive wording and extra suggestions. Only aggregates are transmitted —
 * no user id, device id, raw readings, journal text or check-in notes. Any
 * failure returns an empty result so the dashboard keeps working with the
 * rule-based recommendations.</p>
 */
@Component
public class PhysicalInsightAiClient {

    private static final Logger log = LoggerFactory.getLogger(PhysicalInsightAiClient.class);

    public record AiResult(boolean available, List<InsightDtos.Recommendation> recommendations,
                           String note) {
        static AiResult unavailable() {
            return new AiResult(false, List.of(), null);
        }
    }

    private final RestTemplate restTemplate;
    private final String aiBaseUrl;
    private final String internalApiKey;

    public PhysicalInsightAiClient(
            RestTemplate restTemplate,
            @Value("${mindease.ai.service-url:http://ai-service:8000/api/v1}") String aiBaseUrl,
            @Value("${mindease.ai.internal-api-key:}") String internalApiKey) {
        this.restTemplate = restTemplate;
        this.aiBaseUrl = aiBaseUrl;
        this.internalApiKey = internalApiKey;
    }

    @SuppressWarnings("unchecked")
    public AiResult suggest(MindBodyPatternEngine.WellnessContext context,
                            MindBodyPatternEngine.Result result) {
        if (!result.sufficientData()) {
            return AiResult.unavailable();
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (internalApiKey != null && !internalApiKey.isBlank()) {
                headers.set("X-Internal-API-Key", internalApiKey);
            }

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("window_days", result.coverage().windowDays());
            body.put("coverage", Map.of(
                    "activity_days", result.coverage().daysWithActivity(),
                    "sleep_days", result.coverage().daysWithSleep(),
                    "hydration_days", result.coverage().daysWithHydration(),
                    "mood_checkins", result.coverage().moodCheckins()));
            List<Map<String, Object>> patterns = new ArrayList<>();
            for (InsightDtos.PatternInsight insight : result.insights()) {
                Map<String, Object> pattern = new LinkedHashMap<>();
                pattern.put("id", insight.id());
                pattern.put("severity", insight.severity());
                pattern.put("confidence", insight.confidence());
                pattern.put("summary", insight.summary());
                patterns.add(pattern);
            }
            body.put("patterns", patterns);
            body.put("existing_recommendations", result.recommendations().stream()
                    .map(InsightDtos.Recommendation::id).toList());
            body.put("goals", Map.of(
                    "hydration_target_ml", context.hydrationTarget() == null
                            ? 0 : context.hydrationTarget(),
                    "sleep_target_minutes", context.sleepTarget() == null
                            ? 0 : context.sleepTarget()));

            HttpEntity<?> entity = new HttpEntity<>(body, headers);
            var response = restTemplate.postForEntity(
                    aiBaseUrl + "/wellness/physical-insights", entity, Map.class);
            Object raw = response.getBody() == null ? null : response.getBody().get("recommendations");
            if (!(raw instanceof List<?> list)) {
                return AiResult.unavailable();
            }
            List<InsightDtos.Recommendation> recommendations = new ArrayList<>();
            for (Object item : list) {
                if (!(item instanceof Map<?, ?> map)) {
                    continue;
                }
                String id = stringValue(map.get("id"));
                String title = stringValue(map.get("title"));
                String description = stringValue(map.get("description"));
                String category = stringValue(map.get("category"));
                if (id == null || title == null || description == null) {
                    continue;
                }
                recommendations.add(new InsightDtos.Recommendation(
                        "ai_" + id.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_]", "_"),
                        title, description,
                        category == null ? "WELLNESS" : category, "AI_SERVICE"));
                if (recommendations.size() >= 3) {
                    break;
                }
            }
            String note = stringValue(response.getBody() == null
                    ? null : response.getBody().get("note"));
            return new AiResult(true, recommendations, note);
        } catch (Exception e) {
            log.warn("AI wellness insight unavailable, keeping rule-based insights: {}",
                    e.getMessage());
            return AiResult.unavailable();
        }
    }

    private static String stringValue(Object value) {
        if (value == null) {
            return null;
        }
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }
}
