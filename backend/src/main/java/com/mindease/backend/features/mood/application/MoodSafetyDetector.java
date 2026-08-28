package com.mindease.backend.features.mood.application;

import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Component;

/**
 * Detects crisis-related content in mood notes and text input.
 * Does NOT diagnose — simply identifies concerning keywords for safety escalation.
 * Uses a controlled keyword list reviewed by mental health professionals.
 *
 * Safety policy: when concerning content is detected, the system provides
 * supportive crisis guidance and resource information rather than normal
 * wellness guidance only.
 */
@Component
public class MoodSafetyDetector {

    /** Crisis keywords that indicate potential self-harm or severe distress. */
    private static final List<String> CRISIS_KEYWORDS = List.of(
            "kill myself", "end my life", "want to die", "suicide",
            "self harm", "hurt myself", "end it all", "no reason to live",
            "better off dead", "not worth living", "plan to end",
            "overdose", "cutting myself", "hang myself",
            "want to disappear", "wish i was dead", "give up on life",
            "cant go on", "cant take it anymore", "nothing matters"
    );

    /** Elevated risk keywords — not immediate crisis but warrant attention. */
    private static final List<String> ELEVATED_RISK_KEYWORDS = List.of(
            "hopeless", "worthless", "trapped", "burden",
            "no hope", "helpless", "cantcope", "cant cope",
            "isolated", "alone", "nobody cares", "everyone would be better",
            "severe depression", "cant sleep", "nightmares",
            "panic", "anxiety attack", "cant breathe"
    );

    /**
     * Analyse text for safety concerns.
     *
     * @param text the user's mood note or text input
     * @return safety analysis result with flag, level, and resources
     */
    public Map<String, Object> analyze(String text) {
        Map<String, Object> result = new java.util.LinkedHashMap<>();

        if (text == null || text.isBlank()) {
            result.put("flag", false);
            result.put("level", "none");
            result.put("message", null);
            return result;
        }

        String lower = text.toLowerCase().trim();

        // Check for crisis-level keywords
        for (String keyword : CRISIS_KEYWORDS) {
            if (lower.contains(keyword)) {
                result.put("flag", true);
                result.put("level", "crisis");
                result.put("message", "We noticed something concerning in what you shared. "
                        + "Your safety matters to us.");
                result.put("resources", getCrisisResources());
                return result;
            }
        }

        // Check for elevated risk keywords
        for (String keyword : ELEVATED_RISK_KEYWORDS) {
            if (lower.contains(keyword)) {
                result.put("flag", true);
                result.put("level", "elevated");
                result.put("message", "It sounds like you may be going through a difficult time. "
                        + "Support is available if you need it.");
                result.put("resources", getSupportResources());
                return result;
            }
        }

        result.put("flag", false);
        result.put("level", "none");
        result.put("message", null);
        return result;
    }

    private Map<String, String> getCrisisResources() {
        Map<String, String> resources = new java.util.LinkedHashMap<>();
        resources.put("helpline", "988 Suicide & Crisis Lifeline: Call or text 988");
        resources.put("crisisText", "Crisis Text Line: Text HOME to 741741");
        resources.put("international", "International Association for Suicide Prevention: https://www.iasp.info/resources/Crisis_Centres/");
        resources.put("message", "If you are in immediate danger, please call your local emergency number.");
        return resources;
    }

    private Map<String, String> getSupportResources() {
        Map<String, String> resources = new java.util.LinkedHashMap<>();
        resources.put("helpline", "988 Suicide & Crisis Lifeline: Call or text 988");
        resources.put("crisisText", "Crisis Text Line: Text HOME to 741741");
        resources.put("message", "You are not alone. Reaching out for support is a sign of strength.");
        return resources;
    }
}
