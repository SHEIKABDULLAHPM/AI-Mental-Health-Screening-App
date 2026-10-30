package com.mindease.backend.wellness.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import com.mindease.backend.wellness.domain.WellnessAnalysisRecord;
import com.mindease.backend.wellness.domain.WellnessAnalysisRecordRepository;
import com.mindease.backend.wellness.dto.WellnessAdviceDto;
import com.mindease.backend.wellness.dto.WellnessComparisonDto;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

/**
 * Shared orchestration for the three analysis buttons.
 *
 * <p>Each caller gathers its own data and applies its own deterministic rules;
 * this class then (1) diffs against the previous stored analysis of the same
 * type, (2) asks the AI service to personalise the wording, and (3) persists
 * the result so the next run has a baseline. Persisting is what makes
 * "what changed since last time" real rather than recomputed guesswork.</p>
 */
@Component
public class WellnessAnalysisPipeline {

    private static final Logger log = LoggerFactory.getLogger(WellnessAnalysisPipeline.class);
    private static final String SCHEMA_VERSION = "2.0";
    private static final int WINDOW_DAYS = 30;

    /** Everything the caller renders, after comparison and personalisation. */
    public record Outcome(String recordId,
                          Instant analyzedAt,
                          WellnessComparisonDto comparison,
                          String narrative,
                          List<String> recommendations,
                          List<WellnessAdviceDto> advice,
                          List<String> focusAreas,
                          List<String> nextActions,
                          String generatedBy) {
    }

    private final WellnessAnalysisRecordRepository repository;
    private final WellnessComparisonBuilder comparisonBuilder;
    private final WellnessAnalysisAiClient aiClient;

    public WellnessAnalysisPipeline(WellnessAnalysisRecordRepository repository,
                                    WellnessComparisonBuilder comparisonBuilder,
                                    WellnessAnalysisAiClient aiClient) {
        this.repository = repository;
        this.comparisonBuilder = comparisonBuilder;
        this.aiClient = aiClient;
    }

    public Outcome run(String userId,
                       String type,
                       List<WellnessMetricDto> metrics,
                       List<String> patterns,
                       String ruleNarrative,
                       List<String> ruleRecommendations,
                       Integer primaryScore,
                       String status,
                       List<String> inputReferences) {

        WellnessAnalysisRecord previous;
        try {
            previous = repository
                    .findFirstByUserIdAndTypeOrderByAnalyzedAtDesc(userId, type)
                    .orElse(null);
        } catch (Exception e) {
            // A read failure must not break the analysis; it just means this
            // run is treated as the first stored one.
            log.warn("Could not read previous {} analysis: {}", type, e.getMessage());
            previous = null;
        }

        WellnessComparisonDto comparison = comparisonBuilder.build(previous, metrics);

        WellnessAnalysisAiClient.AiAnalysis ai = aiClient.analyze(
                type, WINDOW_DAYS, metrics, patterns, comparison, ruleRecommendations);

        List<String> recommendations;
        List<WellnessAdviceDto> advice;
        String narrative;
        List<String> focusAreas;
        String generatedBy;

        if (ai.available() && !ai.advice().isEmpty()) {
            advice = ai.advice();
            recommendations = advice.stream().map(WellnessAdviceDto::title).toList();
            narrative = ai.narrative() != null ? ai.narrative() : ruleNarrative;
            focusAreas = ai.focusAreas().isEmpty() ? focusFromComparison(comparison) : ai.focusAreas();
            generatedBy = ai.generatedBy();
        } else {
            advice = List.of();
            recommendations = ruleRecommendations;
            narrative = ruleNarrative;
            focusAreas = focusFromComparison(comparison);
            generatedBy = "rules";
        }

        List<String> nextActions = mergeNextActions(comparison, ai.nextActions());

        WellnessAnalysisRecord record = new WellnessAnalysisRecord();
        record.setUserId(userId);
        record.setType(type);
        record.setAnalyzedAt(Instant.now());
        record.setAvailable(true);
        record.setPrimaryScore(primaryScore);
        record.setStatus(status);
        record.setNarrative(narrative);
        record.setRecommendations(new ArrayList<>(recommendations));
        record.setAdvice(toRecordAdvice(advice));
        record.setFocusAreas(new ArrayList<>(focusAreas));
        record.setNextActions(new ArrayList<>(nextActions));
        record.setGeneratedBy(generatedBy);
        record.setSchemaVersion(SCHEMA_VERSION);
        record.setPatterns(new ArrayList<>(patterns));
        record.setInputReferences(new ArrayList<>(inputReferences == null ? List.of() : inputReferences));
        record.setComparisonOverall(comparison.overall());
        record.setComparisonSummary(comparison.summary());

        Map<String, Double> values = new LinkedHashMap<>();
        Map<String, String> labels = new LinkedHashMap<>();
        Map<String, String> units = new LinkedHashMap<>();
        for (WellnessMetricDto metric : metrics) {
            values.put(metric.key(), metric.value());
            labels.put(metric.key(), metric.label());
            units.put(metric.key(), metric.unit() == null ? "" : metric.unit());
        }
        record.setMetrics(values);
        record.setMetricLabels(labels);
        record.setMetricUnits(units);

        String recordId = null;
        try {
            recordId = repository.save(record).getId();
        } catch (Exception e) {
            // The user still gets their analysis; only history is lost.
            log.error("Could not persist {} analysis for comparison history: {}",
                    type, e.getMessage());
        }

        return new Outcome(recordId, record.getAnalyzedAt(), comparison, narrative,
                List.copyOf(recommendations), List.copyOf(advice),
                List.copyOf(focusAreas), List.copyOf(nextActions), generatedBy);
    }

    /** Stored analyses, newest first, for the history view. */
    public List<WellnessAnalysisRecord> history(String userId, String type) {
        if (type == null) {
            return repository.findTop10ByUserIdOrderByAnalyzedAtDesc(userId);
        }
        return repository.findTop10ByUserIdAndTypeOrderByAnalyzedAtDesc(userId, type);
    }

    private List<String> mergeNextActions(WellnessComparisonDto comparison,
                                         List<String> fromAi) {
        LinkedHashSet<String> actions = new LinkedHashSet<>();
        if (fromAi != null) {
            actions.addAll(fromAi);
        }
        // The AI and the comparison builder can both produce a "keep doing"
        // line; showing two near-identical targets is noise, so keep the first.
        boolean hasKeepDoing = actions.stream()
                .anyMatch(a -> a.toLowerCase(java.util.Locale.ROOT).startsWith("keep doing"));
        for (String candidate : comparisonBuilder.nextActionsFrom(comparison)) {
            if (hasKeepDoing
                    && candidate.toLowerCase(java.util.Locale.ROOT).startsWith("keep doing")) {
                continue;
            }
            actions.add(candidate);
        }
        List<String> merged = new ArrayList<>(actions);
        return merged.size() > 6 ? merged.subList(0, 6) : merged;
    }

    private List<String> focusFromComparison(WellnessComparisonDto comparison) {
        List<String> focus = new ArrayList<>();
        if (!comparison.declined().isEmpty()) {
            focus.add("reversing the recent decline in " + comparison.declined().get(0));
        }
        if (!comparison.improved().isEmpty()) {
            focus.add("holding on to " + comparison.improved().get(0));
        }
        if (focus.isEmpty()) {
            focus.add("keeping your current routine steady");
        }
        return focus;
    }

    private List<WellnessAnalysisRecord.Advice> toRecordAdvice(List<WellnessAdviceDto> advice) {
        List<WellnessAnalysisRecord.Advice> stored = new ArrayList<>();
        for (WellnessAdviceDto item : advice) {
            stored.add(new WellnessAnalysisRecord.Advice(
                    item.title(), item.description(), item.category()));
        }
        return stored;
    }
}
