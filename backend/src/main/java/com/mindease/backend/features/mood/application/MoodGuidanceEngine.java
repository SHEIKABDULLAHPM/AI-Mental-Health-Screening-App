package com.mindease.backend.features.mood.application;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

import org.springframework.stereotype.Component;

/**
 * Generates mood-appropriate wellness guidance and reflection prompts.
 * Provides controlled, evidence-based wellness suggestions — never medical advice.
 * Guidance is tied to the user's self-reported mood and detected emotional state.
 */
@Component
public class MoodGuidanceEngine {

    /** Reflection prompt banks keyed by mood category. */
    private static final Map<String, List<String>> REFLECTION_PROMPTS = new HashMap<>();
    static {
        REFLECTION_PROMPTS.put("very_happy", List.of(
                "What contributed to your positive mood today?",
                "Is there something you would like to reflect on or savour?",
                "How might you share this positive feeling with others?"
        ));
        REFLECTION_PROMPTS.put("happy", List.of(
                "What helped you feel good today?",
                "Is there a moment from today you would like to remember?",
                "What activities contributed to your positive mood?"
        ));
        REFLECTION_PROMPTS.put("calm", List.of(
                "What helped you feel settled today?",
                "Is there something you would like to reflect on?",
                "What does feeling calm mean to you right now?"
        ));
        REFLECTION_PROMPTS.put("okay", List.of(
                "What affected your mood today?",
                "Is there something on your mind you would like to explore?",
                "How has your day been so far?"
        ));
        REFLECTION_PROMPTS.put("low", List.of(
                "What affected your mood today?",
                "Is there something you would like to talk about or reflect on?",
                "What might help you feel a little better right now?"
        ));
        REFLECTION_PROMPTS.put("stressed", List.of(
                "What is weighing on you most right now?",
                "Is there one thing you could let go of today?",
                "What usually helps you feel less overwhelmed?"
        ));
    }

    /**
     * Generate guidance for the current mood and detected emotional state.
     *
     * @param mood        the fused/confirmed mood ID
     * @param emotion     the detected emotion (may be null)
     * @param sentiment   the detected sentiment (may be null)
     * @param trend       trend direction (may be null)
     * @return structured guidance with actions, message, and reflection prompt
     */
    public Map<String, Object> generateGuidance(
            String mood,
            String emotion,
            String sentiment,
            String trend) {

        Map<String, Object> result = new HashMap<>();

        // Determine mood category for guidance lookup
        String category = categorizeMood(mood, sentiment);

        // Build the guidance message
        result.put("message", buildMessage(category, trend));

        // Select wellness actions
        result.put("actions", selectActions(category));

        // Select reflection prompt
        result.put("reflectionPrompt", selectReflectionPrompt(mood));

        // Safety check
        result.put("safetyFlag", false);

        return result;
    }

    private String categorizeMood(String mood, String sentiment) {
        if (mood == null) return "okay";

        return switch (mood) {
            case "very_happy", "happy" -> "positive";
            case "calm" -> "calm";
            case "low" -> "low";
            case "stressed" -> "stressed";
            default -> "okay";
        };
    }

    private String buildMessage(String category, String trend) {
        String base = switch (category) {
            case "positive" -> "You are in a good place right now. ";
            case "calm" -> "You are feeling settled and grounded. ";
            case "low" -> "You may be feeling low right now. ";
            case "stressed" -> "You seem to be experiencing some stress. ";
            default -> "Thank you for checking in. ";
        };

        if ("declining".equals(trend)) {
            base += "Your recent entries also show a downward trend. "
                    + "It is okay to not feel your best — taking small steps can help.";
        } else if ("improving".equals(trend)) {
            base += "Your recent entries show improvement — keep up the positive momentum.";
        } else if ("fluctuating".equals(trend)) {
            base += "Your mood has been varying recently. "
                    + "This is natural — moods shift and that is okay.";
        }

        return base;
    }

    private List<Map<String, String>> selectActions(String category) {
        List<Map<String, String>> actions = new ArrayList<>();

        switch (category) {
            case "positive" -> {
                actions.add(action("continue",
                        "Reflect on what helped",
                        "Take a moment to notice what contributed to your good mood."));
                actions.add(action("routine",
                        "Maintain your routine",
                        "Continue with activities that support your wellbeing."));
            }
            case "calm" -> {
                actions.add(action("reflection",
                        "Quiet reflection",
                        "A few minutes of mindful breathing can deepen this calm feeling."));
                actions.add(action("routine",
                        "Gentle activity",
                        "A short walk or light stretching can complement this calm state."));
            }
            case "low" -> {
                actions.add(action("breathing",
                        "5-minute breathing exercise",
                        "Breathe in for 4 counts, hold for 4, exhale for 6. Repeat 5 times."));
                actions.add(action("movement",
                        "Gentle movement",
                        "A short walk or gentle stretch can help shift your energy."));
                actions.add(action("journaling",
                        "Journal reflection",
                        "Writing down your thoughts can help you process your feelings."));
            }
            case "stressed" -> {
                actions.add(action("breathing",
                        "Box breathing",
                        "Breathe in for 4 counts, hold for 4, exhale for 4, hold for 4. Repeat."));
                actions.add(action("break",
                        "Take a short break",
                        "Step away from what you are doing for a few minutes."));
                actions.add(action("relaxation",
                        "Progressive muscle relaxation",
                        "Tense and release each muscle group for 5 seconds, starting from your toes."));
            }
            default -> {
                actions.add(action("reflection",
                        "Quick reflection",
                        "Take a moment to notice how you are feeling right now."));
                actions.add(action("routine",
                        "Check in with yourself",
                        "Ensure you have eaten, hydrated, and taken a break today."));
            }
        }

        return actions;
    }

    private Map<String, String> action(String type, String title, String description) {
        Map<String, String> a = new HashMap<>();
        a.put("type", type);
        a.put("title", title);
        a.put("description", description);
        return a;
    }

    private String selectReflectionPrompt(String mood) {
        List<String> prompts = REFLECTION_PROMPTS.getOrDefault(mood, REFLECTION_PROMPTS.get("okay"));
        return prompts.get(ThreadLocalRandom.current().nextInt(prompts.size()));
    }
}
