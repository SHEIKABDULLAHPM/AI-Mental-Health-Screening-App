package com.mindease.backend.wellness.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.application.PhysicalWellnessAnalysisService;
import com.mindease.backend.features.physical.application.WellnessGoalService;
import com.mindease.backend.features.physical.dto.PhysicalWellnessAnalysisDto;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.wellness.domain.WellnessAnalysisRecord;
import com.mindease.backend.wellness.dto.CombinedWellnessAnalysisDto;
import com.mindease.backend.wellness.dto.MentalWellnessAnalysisDto;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

@Service
public class CombinedWellnessAnalysisService {

    private static final String SCHEMA_VERSION = "1.0";
    private static final String SOURCE = "wellness-combined-analysis";

    private final MentalWellnessAnalysisService mentalService;
    private final PhysicalWellnessAnalysisService physicalService;
    private final WellnessAnalysisPipeline pipeline;
    private final WellnessGoalService wellnessGoalService;

    @org.springframework.beans.factory.annotation.Autowired
    public CombinedWellnessAnalysisService(MentalWellnessAnalysisService mentalService,
                                           PhysicalWellnessAnalysisService physicalService,
                                           WellnessAnalysisPipeline pipeline,
                                           WellnessGoalService wellnessGoalService) {
        this.mentalService = mentalService;
        this.physicalService = physicalService;
        this.pipeline = pipeline;
        this.wellnessGoalService = wellnessGoalService;
    }

    public CombinedWellnessAnalysisService(MentalWellnessAnalysisService mentalService,
                                           PhysicalWellnessAnalysisService physicalService,
                                           WellnessAnalysisPipeline pipeline) {
        this(mentalService, physicalService, pipeline, null);
    }

    public CombinedWellnessAnalysisDto analyze(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new ApiException(ErrorCode.UNAUTHORIZED, "Authentication required");
        }

        MentalWellnessAnalysisDto mental = mentalService.analyze(userId);
        PhysicalWellnessAnalysisDto physical = physicalService.analyze(userId);

        boolean mentalAvailable = mental != null && mental.available();
        boolean physicalAvailable = physical != null && physical.available();
        boolean hasSufficientData = mentalAvailable && physicalAvailable;

        if (!mentalAvailable && !physicalAvailable) {
            return CombinedWellnessAnalysisDto.unavailable(
                    "Insufficient data from both mental and physical domains. Complete a screening and sync your wearable data.");
        }

        StringBuilder narrative = new StringBuilder();
        if (mentalAvailable && mental.wellnessScore() != null) {
            narrative.append("Mental wellness score: ").append(mental.wellnessScore()).append(" out of 100")
                    .append(mental.stressLevel() != null ? " with " + mental.stressLevel().toLowerCase() + " stress" : "")
                    .append(". ");
        }
        if (physicalAvailable && physical.status() != null) {
            narrative.append("Physical wellness status: ").append(physical.status().toLowerCase()).append(". ");
        }
        if (hasSufficientData) {
            narrative.append("There are observable connections between your mental and physical patterns. ");
            if (mental.stressLevel() != null && "HIGH".equals(mental.stressLevel()) && physical.metrics() != null
                    && physical.metrics().stepsAverage() != null && physical.metrics().stepsAverage() < 5000) {
                narrative.append("Higher stress appears alongside lower activity levels - gentle movement may help. ");
            } else if (mental.stressLevel() != null && "HIGH".equals(mental.stressLevel())) {
                narrative.append("Prioritize stress management alongside maintaining consistent daily routines. ");
            } else {
                narrative.append("Keep up balanced routines across both mental and physical wellness. ");
            }
        } else if (mentalAvailable && !physicalAvailable) {
            narrative.append("Physical data is limited; focus on mental wellness strategies while syncing your wearable device for a fuller picture.");
        } else if (physicalAvailable && !mentalAvailable) {
            narrative.append("Mental assessment data is limited; complete a screening to enable full combined analysis.");
        }

        List<CombinedWellnessAnalysisDto.Suggestion> suggestions = new ArrayList<>();
        if (mentalAvailable && mental.safetyFlag()) {
            suggestions.add(new CombinedWellnessAnalysisDto.Suggestion(
                    "Prioritize Safety Support", "Use available crisis/support resources if you need immediate help.", "SAFETY"));
        }
        if (mentalAvailable && mental.stressLevel() != null && ("HIGH".equals(mental.stressLevel()) || "MODERATE".equals(mental.stressLevel()))) {
            suggestions.add(new CombinedWellnessAnalysisDto.Suggestion(
                    "Stress Regulation", "Try brief breathing exercises or a short walk to help regulate stress.", "MENTAL"));
        }
        if (physicalAvailable && physical.metrics() != null && physical.metrics().stepsAverage() != null
                && physical.metrics().stepsAverage() < 7000) {
            suggestions.add(new CombinedWellnessAnalysisDto.Suggestion(
                    "Increase Movement", "Aim for a short daily walk to gradually build activity levels.", "PHYSICAL"));
        }
        if (physicalAvailable && physical.metrics() != null && physical.metrics().sleepHoursAverage() != null
                && physical.metrics().sleepHoursAverage() < 7) {
            suggestions.add(new CombinedWellnessAnalysisDto.Suggestion(
                    "Improve Sleep Routine", "Establish a consistent wind-down routine for better rest.", "PHYSICAL"));
        }
        if (suggestions.isEmpty()) {
            suggestions.add(new CombinedWellnessAnalysisDto.Suggestion(
                    "Maintain Balance", "Continue your current balanced approach to wellness across both domains.", "GENERAL"));
        }

        List<String> correlations = new ArrayList<>();
        if (hasSufficientData && mental.stressLevel() != null && physical.metrics() != null
                && physical.metrics().stepsAverage() != null) {
            if ("HIGH".equals(mental.stressLevel()) && physical.metrics().stepsAverage() < 6000) {
                correlations.add("Higher stress correlates with lower recent activity (correlation noted, not causation).");
            } else {
                correlations.add("Mental and physical patterns are being tracked together for holistic insights.");
            }
        }

        List<String> cautions = new ArrayList<>();
        if (!hasSufficientData) {
            cautions.add("Analysis is based on partial data from one domain only.");
        }
        cautions.add("Correlations do not imply causation; this is supportive guidance, not medical advice.");

        List<String> inputRefs = new ArrayList<>();
        if (mental != null && mental.provenance() != null) {
            inputRefs.addAll(mental.provenance().inputReferences());
        }
        if (physical != null && physical.provenance() != null) {
            inputRefs.addAll(physical.provenance().inputReferences());
        }

        CombinedWellnessAnalysisDto.InputSummary inputSummary = new CombinedWellnessAnalysisDto.InputSummary(
                mentalAvailable,
                physicalAvailable,
                hasSufficientData,
                mentalAvailable ? mental.wellnessScore() : null,
                physicalAvailable && physical.inputSummary() != null ? physical.inputSummary().daysOfActivity() : null,
                mentalAvailable ? mental.analyzedAt() : null,
                physicalAvailable ? physical.analyzedAt() : null);

        CombinedWellnessAnalysisDto.Provenance provenance = new CombinedWellnessAnalysisDto.Provenance(
                SOURCE,
                SCHEMA_VERSION,
                inputRefs,
                Instant.now());

        boolean safetyFlag = mentalAvailable && mental.safetyFlag();

        // The comparison runs on the same aggregates both sub-analyses expose,
        // so a combined run can be diffed against the previous combined run.
        List<WellnessMetricDto> metrics = new ArrayList<>();
        if (mentalAvailable && mental.wellnessScore() != null) {
            metrics.add(new WellnessMetricDto("wellness_score", "Wellness score",
                    mental.wellnessScore(), "/100"));
        }
        Double stressScore = mentalAvailable ? stressScore(mental.stressLevel()) : null;
        if (stressScore != null) {
            metrics.add(new WellnessMetricDto("stress_level", "Stress level", stressScore, "/100"));
        }
        if (physicalAvailable && physical.metrics() != null
                && physical.metrics().stepsAverage() != null) {
            metrics.add(new WellnessMetricDto("steps_avg", "Daily steps",
                    physical.metrics().stepsAverage(), "steps"));
        }
        if (physicalAvailable && physical.metrics() != null
                && physical.metrics().sleepHoursAverage() != null) {
            metrics.add(new WellnessMetricDto("sleep_hours_avg", "Sleep duration",
                    physical.metrics().sleepHoursAverage(), "h"));
        }

        List<String> patterns = new ArrayList<>(correlations);
        if (mentalAvailable && mental.stressLevel() != null) {
            patterns.add("Mental stress level is " + mental.stressLevel() + ".");
        }
        if (physicalAvailable && physical.status() != null) {
            patterns.add("Physical wellness status is " + physical.status() + ".");
        }

        List<String> ruleRecommendations = suggestions.stream()
                .map(CombinedWellnessAnalysisDto.Suggestion::title)
                .toList();

        WellnessAnalysisPipeline.Outcome outcome = pipeline.run(
                userId,
                WellnessAnalysisRecord.TYPE_COMBINED,
                metrics,
                patterns,
                narrative.toString().trim(),
                ruleRecommendations,
                mentalAvailable ? mental.wellnessScore() : null,
                hasSufficientData ? "BALANCED" : "PARTIAL",
                inputRefs);

        // Keep the structured suggestion shape the existing UI renders, but
        // prefer the personalised advice when the AI service supplied it.
        List<CombinedWellnessAnalysisDto.Suggestion> finalSuggestions = suggestions;
        if (!outcome.advice().isEmpty()) {
            finalSuggestions = outcome.advice().stream()
                    .map(a -> new CombinedWellnessAnalysisDto.Suggestion(
                            a.title(), a.description(), a.category()))
                    .toList();
        }

        // Merge both sub-analyses, preferring the physical (measured) suggestion
        // when both propose the same metric, and never emitting duplicates.
        Map<String, CombinedWellnessAnalysisDto.GoalTargetSuggestion> suggestionByMetric =
                new java.util.LinkedHashMap<>();
        if (mental != null && mental.goalTargetSuggestions() != null) {
            for (MentalWellnessAnalysisDto.GoalTargetSuggestion s : mental.goalTargetSuggestions()) {
                suggestionByMetric.put(s.metric(), new CombinedWellnessAnalysisDto.GoalTargetSuggestion(
                        s.metric(), s.value(), s.unit(), s.rationale()));
            }
        }
        if (physical != null && physical.goalTargetSuggestions() != null) {
            for (PhysicalWellnessAnalysisDto.GoalTargetSuggestion s : physical.goalTargetSuggestions()) {
                suggestionByMetric.put(s.metric(), new CombinedWellnessAnalysisDto.GoalTargetSuggestion(
                        s.metric(), s.value(), s.unit(), s.rationale()));
            }
        }
        List<CombinedWellnessAnalysisDto.GoalTargetSuggestion> goalSuggestions =
                new ArrayList<>(suggestionByMetric.values());

        if (wellnessGoalService != null && !goalSuggestions.isEmpty()) {
            try {
                List<WellnessGoalDtos.AiRecommendation> aiRecs = goalSuggestions.stream()
                        .map(g -> new WellnessGoalDtos.AiRecommendation(g.metric(), g.value(), g.rationale()))
                        .toList();
                wellnessGoalService.applyAiRecommendations(userId, aiRecs);
            } catch (Exception e) {
                // Non-blocking: analysis completes even if goal update encounters an issue
            }
        }

        return new CombinedWellnessAnalysisDto(
                UUID.randomUUID().toString(),
                "COMBINED",
                Instant.now(),
                true,
                hasSufficientData ? "BALANCED" : "PARTIAL",
                outcome.narrative(),
                finalSuggestions,
                correlations,
                cautions,
                outcome.generatedBy(),
                safetyFlag,
                false,
                null,
                inputSummary,
                provenance,
                outcome.advice(),
                outcome.focusAreas(),
                outcome.nextActions(),
                outcome.comparison(),
                goalSuggestions);
    }

    /** Maps the stored stress band onto the comparison scale. */
    private static Double stressScore(String stressLevel) {
        if (stressLevel == null) {
            return null;
        }
        return switch (stressLevel.toUpperCase(java.util.Locale.ROOT)) {
            case "LOW" -> 25.0;
            case "MODERATE", "MEDIUM" -> 55.0;
            case "HIGH", "SEVERE" -> 85.0;
            default -> null;
        };
    }
}
