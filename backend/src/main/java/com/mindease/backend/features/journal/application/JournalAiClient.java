package com.mindease.backend.features.journal.application;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.features.journal.domain.JournalEntry;

/**
 * Calls the Python AI service at :8000/api/v1/journal/analyze for text-based
 * emotion/sentiment analysis and reflection prompts.
 * AI failure must never break journal CRUD — callers receive a fallback.
 */
@Component
public class JournalAiClient {

    private static final Logger log = LoggerFactory.getLogger(JournalAiClient.class);

    private final RestTemplate restTemplate;
    private final String aiBaseUrl;
    private final String internalApiKey;

    public JournalAiClient(
            RestTemplate restTemplate,
            @Value("${mindease.ai.service-url:http://ai-service:8000/api/v1}") String aiBaseUrl,
            @Value("${mindease.ai.internal-api-key:}") String internalApiKey) {
        this.restTemplate = restTemplate;
        this.aiBaseUrl = aiBaseUrl;
        this.internalApiKey = internalApiKey;
    }

    /**
     * Analyze journal text for emotion, sentiment, themes, and reflection.
     * Returns a populated AiAnalysis or a FAILED status — never throws.
     */
    public JournalEntry.AiAnalysis analyzeJournal(String text, int contentVersion) {
        JournalEntry.AiAnalysis fallback = new JournalEntry.AiAnalysis();
        fallback.setStatus("FAILED");
        fallback.setAnalyzedContentVersion(contentVersion);
        fallback.setAnalyzedAt(java.time.Instant.now());

        if (text == null || text.isBlank()) {
            return fallback;
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (internalApiKey != null && !internalApiKey.isBlank()) {
                headers.set("X-Internal-API-Key", internalApiKey);
            }

            var body = Map.<String, Object>of(
                    "text", text.length() > 5000 ? text.substring(0, 5000) : text);

            HttpEntity<?> entity = new HttpEntity<>(body, headers);
            String url = aiBaseUrl + "/journal/analyze";

            log.info("Calling AI service for journal analysis: {}", url);
            var response = restTemplate.postForEntity(url, entity, Map.class);

            if (response.getBody() != null) {
                return parseResponse(response.getBody(), contentVersion);
            }
        } catch (Exception e) {
            log.warn("AI service unavailable for journal analysis: {}", e.getMessage());
        }

        return fallback;
    }

    @SuppressWarnings("unchecked")
    private JournalEntry.AiAnalysis parseResponse(Map<String, Object> body, int contentVersion) {
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();

        String status = (String) body.getOrDefault("status", "COMPLETED");
        if (!"COMPLETED".equals(status) && !"LOW_CONFIDENCE".equals(status)) {
            ai.setStatus("FAILED");
            return ai;
        }

        ai.setStatus("COMPLETED");
        ai.setEmotion((String) body.get("emotion"));
        ai.setSentiment((String) body.get("sentiment"));
        ai.setEmotionalThemes((String) body.get("emotionalThemes"));
        ai.setSummary((String) body.get("summary"));
        ai.setReflectionPrompt((String) body.get("reflectionPrompt"));
        ai.setAnalysisVersion((String) body.getOrDefault("analysisVersion", "journal-emotion-v1"));
        ai.setAnalyzedContentVersion(contentVersion);
        ai.setAnalyzedAt(java.time.Instant.now());

        Object emoConf = body.get("emotionConfidence");
        if (emoConf == null) emoConf = body.get("emotion_confidence");
        if (emoConf instanceof Number n) ai.setEmotionConfidence(n.doubleValue());

        Object sentConf = body.get("sentimentConfidence");
        if (sentConf == null) sentConf = body.get("sentiment_confidence");
        if (sentConf instanceof Number n) ai.setSentimentConfidence(n.doubleValue());

        return ai;
    }
}
