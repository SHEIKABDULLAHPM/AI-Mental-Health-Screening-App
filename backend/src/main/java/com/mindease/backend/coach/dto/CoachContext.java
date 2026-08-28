package com.mindease.backend.coach.dto;

import java.util.List;
import java.util.Map;

/**
 * Controlled context object built by ContextBuilder for the prompt.
 * Each field is bounded and filtered before being sent to Gemini.
 */
public class CoachContext {

    private String currentMessage;
    private List<Map<String, String>> recentConversation;
    private Map<String, Object> userPreferences;
    private String relevantMoodContext;
    private String relevantJournalContext;
    private String wellnessContext;
    private String validatedScreeningContext;
    private String memoryContext;
    private String retrievedKnowledge;
    private String safetySignals;
    private Map<String, String> contextMetadata;

    public CoachContext() {}

    public String getCurrentMessage() { return currentMessage; }
    public void setCurrentMessage(String currentMessage) { this.currentMessage = currentMessage; }

    public List<Map<String, String>> getRecentConversation() { return recentConversation; }
    public void setRecentConversation(List<Map<String, String>> recentConversation) { this.recentConversation = recentConversation; }

    public Map<String, Object> getUserPreferences() { return userPreferences; }
    public void setUserPreferences(Map<String, Object> userPreferences) { this.userPreferences = userPreferences; }

    public String getRelevantMoodContext() { return relevantMoodContext; }
    public void setRelevantMoodContext(String relevantMoodContext) { this.relevantMoodContext = relevantMoodContext; }

    public String getRelevantJournalContext() { return relevantJournalContext; }
    public void setRelevantJournalContext(String relevantJournalContext) { this.relevantJournalContext = relevantJournalContext; }

    public String getWellnessContext() { return wellnessContext; }
    public void setWellnessContext(String wellnessContext) { this.wellnessContext = wellnessContext; }

    public String getValidatedScreeningContext() { return validatedScreeningContext; }
    public void setValidatedScreeningContext(String validatedScreeningContext) { this.validatedScreeningContext = validatedScreeningContext; }

    public String getMemoryContext() { return memoryContext; }
    public void setMemoryContext(String memoryContext) { this.memoryContext = memoryContext; }

    public String getRetrievedKnowledge() { return retrievedKnowledge; }
    public void setRetrievedKnowledge(String retrievedKnowledge) { this.retrievedKnowledge = retrievedKnowledge; }

    public String getSafetySignals() { return safetySignals; }
    public void setSafetySignals(String safetySignals) { this.safetySignals = safetySignals; }

    public Map<String, String> getContextMetadata() { return contextMetadata; }
    public void setContextMetadata(Map<String, String> contextMetadata) { this.contextMetadata = contextMetadata; }
}
