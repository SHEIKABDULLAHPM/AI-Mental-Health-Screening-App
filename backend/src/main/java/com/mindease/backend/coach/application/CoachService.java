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
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.coach.domain.CoachMemory;
import com.mindease.backend.coach.domain.CoachMemoryRepository;
import com.mindease.backend.coach.domain.Message;
import com.mindease.backend.coach.dto.CoachContext;
import com.mindease.backend.coach.dto.MessageResponse;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Orchestrates the full AI Coach pipeline:
 * User Message → Safety → Context → RAG → Prompt → Gemini → Validation → Persist
 */
@Service
public class CoachService {

    private static final Logger log = LoggerFactory.getLogger(CoachService.class);

    private final ConversationService conversationService;
    private final ContextBuilder contextBuilder;
    private final SafetyClassifier safetyClassifier;
    private final GeminiClient geminiClient;
    private final ObjectMapper objectMapper;
    private final CoachMemoryRepository memoryRepo;
    private final RestTemplate restTemplate;

    @Value("${mindease.coach.rag-enabled:true}")
    private boolean ragEnabled;

    @Value("${mindease.coach.max-conversation-history:20}")
    private int maxConversationHistory;

    @Value("${mindease.ai.service-url:http://ai-service:8000/api/v1}")
    private String aiBaseUrl = "http://ai-service:8000/api/v1";

    @Value("${mindease.ai.internal-api-key:}")
    private String internalApiKey = "";

    public CoachService(
            ConversationService conversationService,
            ContextBuilder contextBuilder,
            SafetyClassifier safetyClassifier,
            GeminiClient geminiClient,
            ObjectMapper objectMapper,
            CoachMemoryRepository memoryRepo,
            @Qualifier("geminiRestTemplate") RestTemplate restTemplate) {
        this.conversationService = conversationService;
        this.contextBuilder = contextBuilder;
        this.safetyClassifier = safetyClassifier;
        this.geminiClient = geminiClient;
        this.objectMapper = objectMapper;
        this.memoryRepo = memoryRepo;
        this.restTemplate = restTemplate;
    }

    /**
     * Process a user message and generate an AI response.
     * Returns the assistant MessageResponse.
     */
    public MessageResponse processMessage(String userId, String conversationId, String userMessage) {
        // 1. Safety classification
        String safetyState = safetyClassifier.classify(userMessage);

        // 2. Store user message
        Message userMsg = conversationService.storeUserMessage(userId, conversationId,
                new com.mindease.backend.coach.dto.SendMessageRequest(userMessage, null));

        // 3. Create pending assistant message
        Message pendingMsg = conversationService.createPendingAssistantMessage(
                userId, conversationId, null);

        try {
            // 4. Build context
            CoachContext ctx = contextBuilder.buildContext(userId, conversationId, userMessage);

            // 5. RAG retrieval (best-effort, non-blocking)
            if (ragEnabled) {
                String knowledge = retrieveWellnessKnowledge(userMessage);
                ctx.setRetrievedKnowledge(knowledge);
            }

            // 6. Build prompts
            String systemPrompt = PromptBuilder.buildSystemPrompt(safetyState);
            String userPrompt = PromptBuilder.buildUserPrompt(ctx);

            // 7. Call Gemini
            GeminiClient.GeminiResponse geminiResponse = geminiClient.generate(systemPrompt, userPrompt);

            // 8. Validate and extract response
            if (geminiResponse == null || geminiResponse.text == null || geminiResponse.text.isBlank()) {
                Message failed = conversationService.failAssistantMessage(pendingMsg);
                return MessageResponse.from(failed);
            }

            // Parse structured response
            ParsedResponse parsed = parseAiResponse(geminiResponse.text);

            // 9. Validate response content
            if (!validateResponse(parsed.message)) {
                parsed.message = "I want to make sure I give you a thoughtful response. "
                        + "Could you tell me a bit more about what's on your mind?";
                parsed.suggestions = List.of();
                parsed.reflectionPrompt = null;
            }

            // 10. Safety validation on AI output
            String outputSafetyState = safetyState; // Inherit user's safety state
            if (safetyClassifier.requiresSpecialHandling(safetyState)) {
                // Ensure crisis response includes crisis resources
                if (!parsed.message.toLowerCase().contains("crisis")
                        && !parsed.message.toLowerCase().contains("helpline")
                        && !parsed.message.toLowerCase().contains("988")
                        && !parsed.message.toLowerCase().contains("reach out")) {
                    parsed.message += "\n\nPlease consider reaching out to a crisis helpline "
                            + "or someone you trust. You deserve support right now.";
                }
            }

            // 11. Persist assistant message
            String suggestionsJson = null;
            if (parsed.suggestions != null && !parsed.suggestions.isEmpty()) {
                try {
                    suggestionsJson = objectMapper.writeValueAsString(parsed.suggestions);
                } catch (Exception e) {
                    // Skip suggestions serialization failure
                }
            }

            Message completed = conversationService.completeAssistantMessage(
                    pendingMsg,
                    parsed.message,
                    outputSafetyState,
                    suggestionsJson,
                    geminiResponse.model,
                    PromptBuilder.PROMPT_VERSION);

            // 12. Background: extract and store memory (fire-and-forget)
            extractAndStoreMemory(userId, conversationId, userMessage, parsed.message);

            return MessageResponse.from(completed);

        } catch (Exception e) {
            log.warn("coach_generation_failed userId={} conversationId={} error={}",
                    userId, conversationId, e.getMessage());
            Message failed = conversationService.failAssistantMessage(pendingMsg);
            return MessageResponse.from(failed);
        }
    }

    /**
     * Attempt to retrieve relevant wellness knowledge from the AI service RAG.
     * Best-effort: returns null on failure.
     */
    private String retrieveWellnessKnowledge(String query) {
        try {
            // Call the AI service RAG endpoint for wellness knowledge
            // This is a best-effort retrieval; failure is non-blocking
            String url = aiBaseUrl + "/rag/retrieve";
            Map<String, Object> request = Map.of("query", query);
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (internalApiKey != null && !internalApiKey.isBlank()) {
                headers.set("X-Internal-Api-Key", internalApiKey);
            }
            @SuppressWarnings("unchecked")
            var response = (Map<String, Object>) restTemplate.postForObject(
                    url, new HttpEntity<>(request, headers), Map.class);
            if (response != null && response.containsKey("chunks")) {
                @SuppressWarnings("unchecked")
                List<String> chunks = (List<String>) response.get("chunks");
                if (chunks != null && !chunks.isEmpty()) {
                    StringBuilder sb = new StringBuilder();
                    for (String chunk : chunks) {
                        if (chunk != null && !chunk.isBlank()) {
                            sb.append("- ").append(chunk).append("\n");
                        }
                    }
                    return sb.length() > 0 ? sb.toString() : null;
                }
            }
        } catch (Exception e) {
            // RAG failure is non-blocking
            log.debug("rag_retrieval_failed: {}", e.getMessage());
        }
        return null;
    }

    /**
     * Parse AI response. Expects JSON with message, suggestions, reflectionPrompt.
     */
    private ParsedResponse parseAiResponse(String raw) {
        ParsedResponse result = new ParsedResponse();
        try {
            // Try to parse as JSON
            @SuppressWarnings("unchecked")
            Map<String, Object> json = objectMapper.readValue(raw, Map.class);
            result.message = (String) json.getOrDefault("message", raw);
            if (json.containsKey("suggestions")) {
                result.suggestions = objectMapper.convertValue(json.get("suggestions"),
                        objectMapper.getTypeFactory().constructCollectionType(List.class, String.class));
            }
            result.reflectionPrompt = (String) json.get("reflectionPrompt");
        } catch (Exception e) {
            // If not valid JSON, use the raw text as the message
            result.message = raw;
            result.suggestions = List.of();
        }
        return result;
    }

    /**
     * Validate response content for safety and quality.
     */
    private boolean validateResponse(String message) {
        if (message == null || message.isBlank()) return false;
        if (message.length() > 5000) return false;
        // Check for system prompt leakage
        String lower = message.toLowerCase();
        if (lower.contains("system prompt") || lower.contains("internal policy")
                || lower.contains("i am an ai") || lower.contains("as an ai language model")) {
            return false;
        }
        return true;
    }

    /**
     * Extract useful memories from the conversation (fire-and-forget).
     * Only stores non-sensitive, user-relevant preferences.
     */
    private void extractAndStoreMemory(String userId, String conversationId,
            String userMessage, String aiResponse) {
        try {
            // Simple heuristic-based memory extraction
            // In production, this could use a small LLM call or rule-based system
            String lower = userMessage.toLowerCase();

            // Detect preference patterns
            if (lower.contains("i prefer") || lower.contains("i like") || lower.contains("i enjoy")) {
                storeMemory(userId, conversationId, "preference",
                        extractPreference(userMessage), 0.6);
            } else if (lower.contains("i struggle with") || lower.contains("i have trouble")) {
                storeMemory(userId, conversationId, "coping_preference",
                        extractPreference(userMessage), 0.5);
            } else if (lower.contains("my goal") || lower.contains("i want to")) {
                storeMemory(userId, conversationId, "wellness_goal",
                        extractPreference(userMessage), 0.6);
            }
        } catch (Exception e) {
            // Memory extraction failure is non-blocking
            log.debug("memory_extraction_failed: {}", e.getMessage());
        }
    }

    private void storeMemory(String userId, String conversationId,
            String category, String content, double confidence) {
        if (content == null || content.isBlank() || content.length() < 5) return;

        CoachMemory memory = new CoachMemory();
        memory.setUserId(userId);
        memory.setCategory(category);
        memory.setContent(content);
        memory.setConfidence(confidence);
        memory.setSourceConversationId(conversationId);
        memory.setConfirmed(false);
        memory.setCreatedAt(java.time.Instant.now());
        memory.setUpdatedAt(java.time.Instant.now());
        memoryRepo.save(memory);
    }

    private String extractPreference(String message) {
        // Simple extraction: take the sentence containing the preference keyword
        String[] sentences = message.split("[.!]");
        for (String s : sentences) {
            String lower = s.toLowerCase().trim();
            if (lower.contains("prefer") || lower.contains("like") || lower.contains("enjoy")
                    || lower.contains("struggle") || lower.contains("trouble")
                    || lower.contains("goal") || lower.contains("want to")) {
                return s.trim();
            }
        }
        return message.length() > 200 ? message.substring(0, 200) : message;
    }

    private static class ParsedResponse {
        String message;
        List<String> suggestions;
        String reflectionPrompt;
    }
}
