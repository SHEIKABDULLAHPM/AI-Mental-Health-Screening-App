package com.mindease.backend.coach.application;

import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Client for Google Gemini API. All API key handling happens server-side.
 * The key is NEVER exposed to Flutter or logged.
 */
@Component
public class GeminiClient {

    private static final Logger log = LoggerFactory.getLogger(GeminiClient.class);
    private static final String MODEL_BASE = "https://generativelanguage.googleapis.com/v1beta/models/";

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    @Value("${mindease.gemini.api-key:}")
    private String apiKey;

    @Value("${mindease.gemini.model:gemini-3.5-flash}")
    private String model;

    @Value("${mindease.gemini.timeout-seconds:30}")
    private int timeoutSeconds;

    @Value("${mindease.gemini.max-output-tokens:1024}")
    private int maxOutputTokens;

    @Value("${mindease.gemini.temperature:0.7}")
    private double temperature;

    public GeminiClient(@Qualifier("geminiRestTemplate") RestTemplate restTemplate, ObjectMapper objectMapper) {
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
    }

    /**
     * Send a prompt to Gemini and return the text response.
     * Returns null on failure — never throws to the caller.
     */
    public GeminiResponse generate(String systemPrompt, String userPrompt) {
        if (apiKey == null || apiKey.isBlank()) {
            log.warn("gemini_api_key_not_configured");
            return null;
        }

        try {
            String url = MODEL_BASE + model + ":generateContent?key=" + apiKey;

            Map<String, Object> requestBody = Map.of(
                    "contents", List.of(
                            Map.of("role", "user", "parts", List.of(
                                    Map.of("text", userPrompt)))),
                    "systemInstruction", Map.of(
                            "parts", List.of(Map.of("text", systemPrompt))),
                    "generationConfig", Map.of(
                            "temperature", temperature,
                            "maxOutputTokens", maxOutputTokens,
                            "topP", 0.95,
                            "topK", 40,
                            "thinkingConfig", Map.of(
                                    "thinkingBudget", 0)));

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(requestBody, headers);

            long start = System.currentTimeMillis();
            ResponseEntity<Map<String, Object>> response = restTemplate.exchange(
                    url,
                    org.springframework.http.HttpMethod.POST,
                    entity,
                    new org.springframework.core.ParameterizedTypeReference<Map<String, Object>>() {});
            long latency = System.currentTimeMillis() - start;

            if (response.getBody() == null) {
                log.warn("gemini_empty_response latency={}ms", latency);
                return null;
            }

            return parseResponse(response.getBody(), latency);

        } catch (Exception e) {
            log.warn("gemini_request_failed error={}", e.getMessage());
            return null;
        }
    }

    @SuppressWarnings("unchecked")
    private GeminiResponse parseResponse(Map<String, Object> body, long latency) {
        try {
            var candidates = (List<Map<String, Object>>) body.get("candidates");
            if (candidates == null || candidates.isEmpty()) {
                log.warn("gemini_no_candidates latency={}ms", latency);
                return null;
            }

            var candidate = candidates.get(0);
            var content = (Map<String, Object>) candidate.get("content");
            if (content == null) return null;

            var parts = (List<Map<String, Object>>) content.get("parts");
            if (parts == null || parts.isEmpty()) return null;

            StringBuilder text = new StringBuilder();
            for (var part : parts) {
                if (part.containsKey("text")) {
                    text.append(part.get("text"));
                }
            }

            if (text.isEmpty()) return null;

            GeminiResponse resp = new GeminiResponse();
            resp.text = text.toString();
            resp.model = model;
            resp.latencyMs = latency;
            resp.finishReason = (String) candidate.getOrDefault("finishReason", "STOP");

            // Extract token usage if available
            var usageMetadata = (Map<String, Object>) body.get("usageMetadata");
            if (usageMetadata != null) {
                resp.promptTokens = ((Number) usageMetadata.getOrDefault("promptTokenCount", 0)).intValue();
                resp.candidatesTokens = ((Number) usageMetadata.getOrDefault("candidatesTokenCount", 0)).intValue();
            }

            log.info("gemini_success model={} latency={}ms promptTokens={} candidateTokens={}",
                    model, latency, resp.promptTokens, resp.candidatesTokens);
            return resp;

        } catch (Exception e) {
            log.warn("gemini_parse_failed latency={}ms error={}", latency, e.getMessage());
            return null;
        }
    }

    public String getModel() { return model; }
    public int getMaxOutputTokens() { return maxOutputTokens; }

    public static class GeminiResponse {
        public String text;
        public String model;
        public long latencyMs;
        public String finishReason;
        public int promptTokens;
        public int candidatesTokens;
    }
}
