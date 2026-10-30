package com.mindease.backend.wellness.application;

import java.util.ArrayList;
import java.util.LinkedHashMap;
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

import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.wellness.dto.CombinedInsightDto;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * Calls the AI service {@code /wellness/combined-insight} endpoint.
 *
 * <p>Only deterministic mental scores and already-aggregated physical coverage
 * are transmitted - never raw answers, journal text, readings, notes or
 * identifiers. Any failure returns an unavailable result so the caller can
 * fall back to the deterministic composer.</p>
 */
@Component
public class CombinedInsightAiClient {

    private static final Logger log = LoggerFactory.getLogger(CombinedInsightAiClient.class);

    public record Result(boolean available, String narrative,
                         List<CombinedInsightDto.Suggestion> suggestions,
                         String generatedBy, String note) {
        static Result unavailable() {
            return new Result(false, null, List.of(), null, null);
        }
    }

    private final RestTemplate restTemplate;
    private final String aiBaseUrl;
    private final String internalApiKey;

    public CombinedInsightAiClient(
            RestTemplate restTemplate,
            @Value("${mindease.ai.service-url:http://ai-service:8000/api/v1}") String aiBaseUrl,
            @Value("${mindease.ai.internal-api-key:}") String internalApiKey) {
        this.restTemplate = restTemplate;
        this.aiBaseUrl = aiBaseUrl;
        this.internalApiKey = internalApiKey;
    }

    @SuppressWarnings("unchecked")
    public Result generate(WellnessProfileDto profile,
                           InsightDtos.InsightsResponse physical) {
        if (profile == null || physical == null) {
            return Result.unavailable();
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (internalApiKey != null && !internalApiKey.isBlank()) {
                headers.set("X-Internal-Api-Key", internalApiKey);
            }

            Map<String, Object> mental = new LinkedHashMap<>();
            mental.put("wellness_score", valueOrZero(profile.wellnessScore()));
            mental.put("stress_level", textOr(profile.stressLevel(), "MODERATE"));
            mental.put("lifestyle_score", valueOrZero(profile.lifestyleScore()));
            mental.put("sleep_quality", textOr(profile.sleepQuality(), "FAIR"));
            mental.put("primary_focus", textOr(profile.primaryFocus(), "BALANCE"));
            mental.put("safety_flag", Boolean.TRUE.equals(profile.safetyFlag()));
            // The stored mood label carries no observation timestamp in this
            // contract. Sending it invited unsupported recency claims such as
            // "you are feeling happy today" for a check-in recorded days ago,
            // so it is intentionally omitted. The deterministic scores already
            // summarise mood support, and the dashboard shows the mood summary
            // with its own date.

            InsightDtos.DataCoverage coverage = physical.coverage();
            Map<String, Object> physicalBody = new LinkedHashMap<>();
            physicalBody.put("window_days", physical.windowDays());
            physicalBody.put("sufficient_data", physical.sufficientData());
            physicalBody.put("coverage", Map.of(
                    "activity_days", coverage.daysWithActivity(),
                    "sleep_days", coverage.daysWithSleep(),
                    "hydration_days", coverage.daysWithHydration(),
                    "mood_checkins", coverage.moodCheckins()));
            physicalBody.put("pattern_ids", physical.insights().stream()
                    .map(InsightDtos.PatternInsight::id)
                    .distinct()
                    .limit(20)
                    .toList());
            List<Map<String, Object>> suggestions = new ArrayList<>();
            for (InsightDtos.Recommendation recommendation : physical.recommendations()) {
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("title", recommendation.title());
                item.put("description", recommendation.description());
                item.put("category", recommendation.category());
                suggestions.add(item);
                if (suggestions.size() >= 3) {
                    break;
                }
            }
            physicalBody.put("suggestions", suggestions);

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("mental", mental);
            body.put("physical", physicalBody);

            var response = restTemplate.postForEntity(
                    aiBaseUrl + "/wellness/combined-insight",
                    new HttpEntity<>(body, headers),
                    Map.class);
            Map<String, Object> data = response.getBody();
            if (data == null) {
                return Result.unavailable();
            }
            String narrative = stringValue(data.get("narrative"));
            if (narrative == null || narrative.length() < 20) {
                return Result.unavailable();
            }
            List<CombinedInsightDto.Suggestion> parsed = new ArrayList<>();
            Object rawSuggestions = data.get("suggestions");
            if (rawSuggestions instanceof List<?> list) {
                for (Object item : list) {
                    if (!(item instanceof Map<?, ?> map)) {
                        continue;
                    }
                    String title = stringValue(map.get("title"));
                    String description = stringValue(map.get("description"));
                    if (title == null || description == null) {
                        continue;
                    }
                    parsed.add(new CombinedInsightDto.Suggestion(
                            title, description,
                            textOr(stringValue(map.get("category")), "WELLNESS")));
                    if (parsed.size() >= 3) {
                        break;
                    }
                }
            }
            String generatedBy = textOr(stringValue(data.get("generated_by")), "rules");
            String note = stringValue(data.get("note"));
            return new Result(true, narrative, parsed, generatedBy, note);
        } catch (Exception e) {
            log.warn("Combined insight AI unavailable, using deterministic composer: {}",
                    e.getMessage());
            return Result.unavailable();
        }
    }

    private static int valueOrZero(Integer value) {
        return value == null ? 0 : value;
    }

    private static String textOr(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private static String stringValue(Object value) {
        if (value == null) {
            return null;
        }
        String text = value.toString().trim();
        return text.isEmpty() ? null : text;
    }
}
