package com.mindease.backend.wellness.application;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.physical.application.PhysicalInsightService;
import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.dto.CombinedInsightDto;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * Combines the deterministic mental profile with the physical pattern context.
 *
 * <p>The mental scores and physical coverage are the only facts used. The AI
 * service may phrase the reflection, but when it is unavailable a deterministic
 * composer produces grounded text from the same aggregates. The PHQ-9 item-9
 * escalation is always applied in Java, never delegated to the model.</p>
 */
@Service
public class CombinedInsightService {

    private static final Logger log = LoggerFactory.getLogger(CombinedInsightService.class);

    /** Why the escalation appeared. Left out when the text already says it. */
    static final String SAFETY_REASON =
            "Because one of your answers mentioned thoughts of self-harm, please reach "
                    + "out to someone you trust today.";
    /**
     * Outreach advice without repeating the cause. Used when the model already
     * names self-harm but does not tell the reader to reach out; the escalation
     * must still contain an actionable request, not only a crisis line.
     */
    static final String SAFETY_OUTREACH =
            "Please reach out to someone you trust today.";
    /**
     * The crisis line. Java always guarantees this sentence once the safety flag
     * is set, no matter what the model wrote.
     */
    static final String SAFETY_CRISIS =
            "If you are in immediate danger, contact your local emergency number or a "
                    + "crisis service now.";
    /** The complete escalation, for callers that want it undeduplicated. */
    static final String SAFETY_SUPPORT = SAFETY_REASON + " " + SAFETY_CRISIS;
    static final String DISCLAIMER =
            "This is guidance, not a diagnosis. It combines your own stored check-in "
                    + "with aggregated physical data; no measurement was invented.";

    private final WellnessProfileService profiles;
    private final PhysicalInsightService physicalInsights;
    private final CombinedInsightAiClient aiClient;
    private final CombinedInsightCache cache;

    public CombinedInsightService(WellnessProfileService profiles,
                                  PhysicalInsightService physicalInsights,
                                  CombinedInsightAiClient aiClient,
                                  CombinedInsightCache cache) {
        this.profiles = profiles;
        this.physicalInsights = physicalInsights;
        this.aiClient = aiClient;
        this.cache = cache;
    }

    public CombinedInsightDto combined(String userId) {
        WellnessProfileDto profile;
        try {
            profile = profiles.currentUser(userId);
        } catch (ApiException e) {
            return CombinedInsightDto.unavailable();
        }
        // Scores/insight are null until the deterministic analysis completes.
        // Never compose a narrative from placeholder defaults.
        if (profile.status() != ProfileStatus.COMPLETED) {
            return new CombinedInsightDto(Instant.now(), false, null, List.of(), null,
                    false, "Your combined insight will appear once your wellness "
                            + "analysis is complete.", false, null);
        }
        InsightDtos.InsightsResponse physical = physicalInsights.insightsWithoutAi(userId);
        String fingerprint = fingerprint(profile, physical);

        Optional<CombinedInsightDto> cached = cache.get(userId, fingerprint);
        if (cached.isPresent()) {
            return cached.get();
        }

        CombinedInsightDto result = build(profile, physical);
        cache.put(userId, fingerprint, result);
        return result;
    }

    private CombinedInsightDto build(WellnessProfileDto profile,
                                     InsightDtos.InsightsResponse physical) {
        CombinedInsightAiClient.Result ai = aiClient.generate(profile, physical);
        String narrative;
        List<CombinedInsightDto.Suggestion> suggestions;
        String generatedBy;
        String note;

        if (ai.available()) {
            narrative = ai.narrative();
            suggestions = new ArrayList<>(ai.suggestions());
            generatedBy = ai.generatedBy() == null ? "llm" : ai.generatedBy();
            note = ai.note() == null ? DISCLAIMER : ai.note();
        } else {
            narrative = deterministicNarrative(profile, physical);
            suggestions = new ArrayList<>(fromPhysical(physical));
            generatedBy = "rules";
            note = DISCLAIMER;
        }

        if (suggestions.isEmpty()) {
            suggestions.add(new CombinedInsightDto.Suggestion(
                    "A brief grounding pause",
                    "When you have a moment, try five slow breaths and notice what you "
                            + "can see, hear and feel. Keep logging so patterns can emerge.",
                    "MINDFULNESS"));
        }

        boolean safetyFlag = Boolean.TRUE.equals(profile.safetyFlag());
        if (safetyFlag) {
            narrative = appendEscalation(narrative);
            boolean hasSupportSuggestion = suggestions.stream()
                    .anyMatch(item -> item.description() != null
                            && item.description().toLowerCase(Locale.ROOT).contains("trust"));
            if (!hasSupportSuggestion) {
                suggestions.add(0, new CombinedInsightDto.Suggestion(
                        "Reach out today",
                        "Tell someone you trust how you are feeling, or contact a local "
                                + "crisis service. You do not have to carry this alone.",
                        "SUPPORT"));
            }
        }
        if (suggestions.size() > 3) {
            suggestions = new ArrayList<>(suggestions.subList(0, 3));
        }

        return new CombinedInsightDto(
                Instant.now(),
                true,
                narrative,
                suggestions,
                generatedBy,
                safetyFlag,
                note,
                false,
                physical.coverage());
    }

    /**
     * Guarantees the self-harm escalation without copying text the model already
     * produced.
     *
     * <p>The escalation belongs to Java and stays un-suppressible: after this
     * call the crisis line is always in the narrative, even when the model says
     * nothing about it. What is avoided is repetition — a sentence whose point
     * is already made (the self-harm answer is named, or the reader is already
     * told to reach out) is not stated twice.</p>
     */
    static String appendEscalation(String narrative) {
        String text = narrative == null ? "" : narrative.trim();
        String lower = text.toLowerCase(Locale.ROOT);

        boolean mentionsCause = lower.contains("self-harm")
                || lower.contains("self harm")
                || lower.contains("harming yourself")
                || lower.contains("suicid");
        boolean alreadyAdvisesOutreach = lower.contains("reach out")
                || lower.contains("someone you trust")
                || lower.contains("trusted person")
                || lower.contains("crisis")
                || lower.contains("emergency");
        boolean hasCrisisLine = lower.contains("emergency number")
                || lower.contains("crisis service")
                || lower.contains("crisis line")
                || lower.contains("helpline");

        List<String> missing = new ArrayList<>();
        if (!alreadyAdvisesOutreach) {
            // Never omit the actionable request just because the model named
            // the cause. Use the cause-bearing sentence only when the cause is
            // not already in the text, so the reader is not told why twice.
            missing.add(mentionsCause ? SAFETY_OUTREACH : SAFETY_REASON);
        }
        if (!hasCrisisLine) {
            missing.add(SAFETY_CRISIS);
        }
        if (missing.isEmpty()) {
            return text;
        }
        String addition = String.join(" ", missing);
        return text.isEmpty() ? addition : text + " " + addition;
    }

    private List<CombinedInsightDto.Suggestion> fromPhysical(
            InsightDtos.InsightsResponse physical) {
        List<CombinedInsightDto.Suggestion> suggestions = new ArrayList<>();
        for (InsightDtos.Recommendation recommendation : physical.recommendations()) {
            suggestions.add(new CombinedInsightDto.Suggestion(
                    recommendation.title(),
                    recommendation.description(),
                    recommendation.category()));
            if (suggestions.size() >= 3) {
                break;
            }
        }
        return suggestions;
    }

    static String deterministicNarrative(WellnessProfileDto profile,
                                         InsightDtos.InsightsResponse physical) {
        InsightDtos.DataCoverage coverage = physical.coverage();
        String stress = switch (profile.stressLevel() == null ? "" : profile.stressLevel()) {
            case "LOW" -> "low";
            case "HIGH" -> "high";
            default -> "moderate";
        };
        String focus = switch (profile.primaryFocus() == null ? "" : profile.primaryFocus()) {
            case "STRESS_MANAGEMENT" -> "managing stress";
            case "SLEEP" -> "restoring sleep";
            case "MOOD_SUPPORT" -> "supporting your mood";
            default -> "keeping a balanced routine";
        };
        String sleep = switch (profile.sleepQuality() == null ? "" : profile.sleepQuality()) {
            case "GOOD" -> "good";
            case "POOR" -> "poor";
            default -> "fair";
        };
        StringBuilder text = new StringBuilder()
                .append("Your recent check-in points to ").append(stress)
                .append(" stress with ").append(focus)
                .append(" as the main focus, and your reported sleep quality is ")
                .append(sleep).append(". ");
        if (physical.sufficientData()) {
            text.append("Over the last ").append(physical.windowDays())
                    .append(" days you logged activity on ").append(coverage.daysWithActivity())
                    .append(" days, sleep on ").append(coverage.daysWithSleep())
                    .append(" nights, hydration on ").append(coverage.daysWithHydration())
                    .append(" days and ").append(coverage.moodCheckins())
                    .append(" mood check-in(s). ");
        } else {
            text.append("There is not enough recent physical data yet to describe a "
                            + "mind-body pattern: activity on ")
                    .append(coverage.daysWithActivity()).append(" of the last ")
                    .append(physical.windowDays()).append(" days and sleep on ")
                    .append(coverage.daysWithSleep()).append(" nights. ");
        }
        text.append("Small, repeatable habits are a reasonable next step, and gentle "
                + "consistency matters more than any single day. ").append(DISCLAIMER);
        return text.toString();
    }

    /**
     * Cache identity: changes whenever the profile or the physical coverage /
     * detected patterns change. The insight text is hashed rather than embedded
     * because it can be large.
     */
    static String fingerprint(WellnessProfileDto profile,
                              InsightDtos.InsightsResponse physical) {
        InsightDtos.DataCoverage coverage = physical.coverage();
        String material = String.join("|",
                String.valueOf(profile.id()),
                String.valueOf(profile.assessmentId()),
                String.valueOf(profile.status()),
                String.valueOf(profile.wellnessScore()),
                String.valueOf(profile.stressLevel()),
                String.valueOf(profile.lifestyleScore()),
                String.valueOf(profile.sleepQuality()),
                String.valueOf(profile.primaryFocus()),
                String.valueOf(profile.safetyFlag()),
                String.valueOf(profile.moodMood()),
                String.valueOf(profile.moodTrendDirection()),
                hash(profile.aiInsight()),
                // The profile's own revision time catches a change to a field
                // the AI contract does not send yet, without waiting for TTL.
                String.valueOf(profile.updatedAt()),
                String.valueOf(physical.windowDays()),
                String.valueOf(physical.sufficientData()),
                String.valueOf(coverage.daysWithActivity()),
                String.valueOf(coverage.daysWithSleep()),
                String.valueOf(coverage.daysWithHydration()),
                String.valueOf(coverage.moodCheckins()),
                String.valueOf(coverage.heartRateDays()),
                String.valueOf(coverage.missingSources()),
                // The AI sees the suggestion wording, not just its id. A rule
                // whose text (e.g. a step total) changed must miss the cache.
                physical.insights().stream()
                        .map(item -> item.id() + "#" + item.title() + "#"
                                + item.summary() + "#" + item.severity())
                        .sorted().reduce("", (a, b) -> a + "," + b),
                physical.recommendations().stream()
                        .map(item -> item.id() + "#" + item.title() + "#"
                                + item.description() + "#" + item.category()
                                + "#" + item.source())
                        .sorted().reduce("", (a, b) -> a + "," + b));
        return hash(material);
    }

    private static String hash(String value) {
        if (value == null) {
            return "-";
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(
                    digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            // SHA-256 is required by the JRE; this is defensive only.
            log.warn("combined_insight_hash_failed reason={}", e.getMessage());
            return Integer.toHexString(value.hashCode());
        }
    }
}
