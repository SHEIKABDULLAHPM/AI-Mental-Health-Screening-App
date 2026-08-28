package com.mindease.backend.features.mood.application;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

import org.springframework.stereotype.Component;

/**
 * Generates mood-appropriate reflection prompts.
 * Reflection prompts are short, open-ended questions that encourage
 * self-awareness without diagnosing or interpreting the user's state.
 */
@Component
public class MoodReflectionPrompts {

    private static final Map<String, List<String>> PROMPTS = Map.of(
            "very_happy", List.of(
                    "What contributed to your positive mood today?",
                    "Is there a moment you would like to remember?",
                    "How might you carry this feeling into tomorrow?"
            ),
            "happy", List.of(
                    "What helped you feel good today?",
                    "Is there something you would like to reflect on?",
                    "What activity or interaction made today better?"
            ),
            "calm", List.of(
                    "What helped you feel settled today?",
                    "Is there something you would like to be mindful of?",
                    "What does feeling calm mean to you right now?"
            ),
            "okay", List.of(
                    "What affected your mood today?",
                    "Is there something on your mind you would like to explore?",
                    "How has your day been so far?"
            ),
            "low", List.of(
                    "What affected your mood today?",
                    "Is there something you would like to talk about or reflect on?",
                    "What might help you feel a little better right now?"
            ),
            "stressed", List.of(
                    "What is weighing on you most right now?",
                    "Is there one thing you could let go of today?",
                    "What usually helps you feel less overwhelmed?"
            )
    );

    /**
     * Get a reflection prompt appropriate for the given mood.
     *
     * @param mood the mood ID
     * @return a single reflection prompt string
     */
    public String getPrompt(String mood) {
        List<String> prompts = PROMPTS.getOrDefault(mood, PROMPTS.get("okay"));
        return prompts.get(ThreadLocalRandom.current().nextInt(prompts.size()));
    }

    /**
     * Get a reflection prompt with metadata for the API response.
     *
     * @param mood the mood ID
     * @return structured map with prompt text and mood context
     */
    public Map<String, String> getStructuredPrompt(String mood) {
        return Map.of(
                "text", getPrompt(mood),
                "moodContext", mood != null ? mood : "okay",
                "type", "reflection"
        );
    }
}
