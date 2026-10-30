package com.mindease.backend.wellness.application;

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

import com.mindease.backend.wellness.dto.WellnessAdviceDto;
import com.mindease.backend.wellness.dto.WellnessComparisonDto;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

/**
 * Client for the AI service's personalised analysis endpoint.
 *
 * <p>Only aggregates are transmitted — no user id, journal text, screening
 * answers or raw readings. Every failure returns {@code null} so the caller
 * keeps its rule-based result: the analysis endpoint must never fail because
 * the LLM is unavailable.</p>
 */
@Component
public class WellnessAnalysisAiClient {

    private static final Logger log = LoggerFactory.getLogger(WellnessAnalysisAiClient.class);

    public record AiAnalysis(boolean available,
                             String narrative,
                             List<WellnessAdviceDto> advice,
                             List<String> focusAreas,
                             List<String> nextActions,
                             String generatedBy) {

        static AiAnalysis unavailable() {
            return new AiAnalysis(false, null, List.of(), List.of(), List.of(), "rules");
        }
    }

    private final RestTemplate restTemplate;
    private final String aiBaseUrl;
    private final String internalApiKey;

    public WellnessAnalysisAiClient(
            RestTemplate restTemplate,
            @Value("${mindease.ai.service-url:http://ai-service:8000/api/v1}") String aiBaseUrl,
            @Value("${mindease.ai.internal-api-key:}") String internalApiKey) {
        this.restTemplate = restTemplate;
        this.aiBaseUrl = aiBaseUrl;
        this.internalApiKey = internalApiKey;
    }

    @SuppressWarnings("unchecked")
    public AiAnalysis analyze(String type,
                              int windowDays,
                              List<WellnessMetricDto> metrics,
                              List<String> patterns,
                              WellnessComparisonDto comparison,
                              List<String> existingRecommendations) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (internalApiKey != null && !internalApiKey.isBlank()) {
                headers.set("X-Internal-API-Key", internalApiKey);
            }

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("type", type);
            body.put("window_days", windowDays);
            body.put("metrics", metrics.stream()
                    .map(m -> {
                        Map<String, Object> item = new LinkedHashMap<>();
                        item.put("key", m.key());
                        item.put("label", m.label());
                        item.put("value", m.value());
                        item.put("unit", m.unit() == null ? "" : m.unit());
                        return item;
                    })
                    .toList());
            body.put("patterns", patterns);
            body.put("existing_recommendations", existingRecommendations);
            if (comparison != null) {
                Map<String, Object> comp = new LinkedHashMap<>();
                comp.put("has_previous", comparison.hasPrevious());
                comp.put("days_since_previous", comparison.daysSincePrevious());
                comp.put("overall", comparison.overall());
                comp.put("improved", comparison.improved());
                comp.put("declined", comparison.declined());
                comp.put("unchanged", comparison.unchanged());
                body.put("comparison", comp);
            }

            HttpEntity<?> entity = new HttpEntity<>(body, headers);
            var response = restTemplate.postForEntity(aiBaseUrl + "/analysis", entity, Map.class);
            Map<String, Object> payload = response.getBody();
            if (payload == null) {
                return AiAnalysis.unavailable();
            }

            String narrative = text(payload.get("narrative"));
            List<WellnessAdviceDto> advice = new ArrayList<>();
            Object rawRecommendations = payload.get("recommendations");
            if (rawRecommendations instanceof List<?> list) {
                for (Object item : list) {
                    if (!(item instanceof Map<?, ?> map)) {
                        continue;
                    }
                    String title = text(map.get("title"));
                    String description = text(map.get("description"));
                    if (title == null || description == null) {
                        continue;
                    }
                    advice.add(new WellnessAdviceDto(
                            title,
                            description,
                            text(map.get("category")) == null
                                    ? "WELLNESS"
                                    : text(map.get("category")).toUpperCase(Locale.ROOT)));
                    if (advice.size() >= 4) {
                        break;
                    }
                }
            }

            List<String> focus = stringList(payload.get("focus_areas"));
            List<String> next = stringList(payload.get("next_actions"));
            String generatedBy = text(payload.get("generated_by"));

            if (narrative == null && advice.isEmpty()) {
                return AiAnalysis.unavailable();
            }
            return new AiAnalysis(true, narrative, advice, focus, next,
                    generatedBy == null ? "rules" : generatedBy);
        } catch (Exception e) {
            log.warn("AI wellness analysis unavailable, keeping rule-based result: {}",
                    e.getMessage());
            return AiAnalysis.unavailable();
        }
    }

    private static String text(Object value) {
        if (value == null) {
            return null;
        }
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }

    private static List<String> stringList(Object value) {
        if (!(value instanceof List<?> list)) {
            return List.of();
        }
        List<String> items = new ArrayList<>();
        for (Object item : list) {
            String text = text(item);
            if (text != null) {
                items.add(text);
            }
        }
        return items;
    }
}
