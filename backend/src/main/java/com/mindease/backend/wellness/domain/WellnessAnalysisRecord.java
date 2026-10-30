package com.mindease.backend.wellness.domain;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One stored analysis run, for any of the three analysis types.
 *
 * <p>The record keeps the numbers the analysis was based on ({@link #metrics})
 * so the next run can compare against them without recomputing history. It is
 * scoped by {@code userId}; every query filters on it.</p>
 */
@Document(collection = "wellness_analysis_records")
@CompoundIndex(name = "user_type_analyzed_idx",
        def = "{'userId': 1, 'type': 1, 'analyzedAt': -1}")
public class WellnessAnalysisRecord {

    /** MENTAL, PHYSICAL or COMBINED. */
    public static final String TYPE_MENTAL = "MENTAL";
    public static final String TYPE_PHYSICAL = "PHYSICAL";
    public static final String TYPE_COMBINED = "COMBINED";

    @Id
    private String id;

    @Indexed
    private String userId;

    private String type;

    private Instant analyzedAt;

    private boolean available;

    /** Headline number used for the quick "improved / declined" verdict. */
    private Integer primaryScore;

    private String status;

    private String narrative;

    /** Numeric inputs, so the next analysis can diff them. */
    private Map<String, Double> metrics = new LinkedHashMap<>();

    /** Human label and unit per metric key, kept for rendering the diff. */
    private Map<String, String> metricLabels = new LinkedHashMap<>();

    private Map<String, String> metricUnits = new LinkedHashMap<>();

    private List<String> patterns = new ArrayList<>();

    private List<String> recommendations = new ArrayList<>();

    private List<Advice> advice = new ArrayList<>();

    private List<String> focusAreas = new ArrayList<>();

    private List<String> nextActions = new ArrayList<>();

    /** "rules" or "llm" — which produced the wording. */
    private String generatedBy;

    private String schemaVersion;

    private List<String> inputReferences = new ArrayList<>();

    private String comparisonOverall;

    private String comparisonSummary;

    public static class Advice {

        private String title;
        private String description;
        private String category;

        public Advice() {
        }

        public Advice(String title, String description, String category) {
            this.title = title;
            this.description = description;
            this.category = category;
        }

        public String getTitle() {
            return title;
        }

        public void setTitle(String title) {
            this.title = title;
        }

        public String getDescription() {
            return description;
        }

        public void setDescription(String description) {
            this.description = description;
        }

        public String getCategory() {
            return category;
        }

        public void setCategory(String category) {
            this.category = category;
        }
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public Instant getAnalyzedAt() {
        return analyzedAt;
    }

    public void setAnalyzedAt(Instant analyzedAt) {
        this.analyzedAt = analyzedAt;
    }

    public boolean isAvailable() {
        return available;
    }

    public void setAvailable(boolean available) {
        this.available = available;
    }

    public Integer getPrimaryScore() {
        return primaryScore;
    }

    public void setPrimaryScore(Integer primaryScore) {
        this.primaryScore = primaryScore;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getNarrative() {
        return narrative;
    }

    public void setNarrative(String narrative) {
        this.narrative = narrative;
    }

    public Map<String, Double> getMetrics() {
        return metrics;
    }

    public void setMetrics(Map<String, Double> metrics) {
        this.metrics = metrics == null ? new LinkedHashMap<>() : metrics;
    }

    public Map<String, String> getMetricLabels() {
        return metricLabels;
    }

    public void setMetricLabels(Map<String, String> metricLabels) {
        this.metricLabels = metricLabels == null ? new LinkedHashMap<>() : metricLabels;
    }

    public Map<String, String> getMetricUnits() {
        return metricUnits;
    }

    public void setMetricUnits(Map<String, String> metricUnits) {
        this.metricUnits = metricUnits == null ? new LinkedHashMap<>() : metricUnits;
    }

    public List<String> getPatterns() {
        return patterns;
    }

    public void setPatterns(List<String> patterns) {
        this.patterns = patterns == null ? new ArrayList<>() : patterns;
    }

    public List<String> getRecommendations() {
        return recommendations;
    }

    public void setRecommendations(List<String> recommendations) {
        this.recommendations = recommendations == null ? new ArrayList<>() : recommendations;
    }

    public List<Advice> getAdvice() {
        return advice;
    }

    public void setAdvice(List<Advice> advice) {
        this.advice = advice == null ? new ArrayList<>() : advice;
    }

    public List<String> getFocusAreas() {
        return focusAreas;
    }

    public void setFocusAreas(List<String> focusAreas) {
        this.focusAreas = focusAreas == null ? new ArrayList<>() : focusAreas;
    }

    public List<String> getNextActions() {
        return nextActions;
    }

    public void setNextActions(List<String> nextActions) {
        this.nextActions = nextActions == null ? new ArrayList<>() : nextActions;
    }

    public String getGeneratedBy() {
        return generatedBy;
    }

    public void setGeneratedBy(String generatedBy) {
        this.generatedBy = generatedBy;
    }

    public String getSchemaVersion() {
        return schemaVersion;
    }

    public void setSchemaVersion(String schemaVersion) {
        this.schemaVersion = schemaVersion;
    }

    public List<String> getInputReferences() {
        return inputReferences;
    }

    public void setInputReferences(List<String> inputReferences) {
        this.inputReferences = inputReferences == null
                ? new ArrayList<>() : inputReferences;
    }

    public String getComparisonOverall() {
        return comparisonOverall;
    }

    public void setComparisonOverall(String comparisonOverall) {
        this.comparisonOverall = comparisonOverall;
    }

    public String getComparisonSummary() {
        return comparisonSummary;
    }

    public void setComparisonSummary(String comparisonSummary) {
        this.comparisonSummary = comparisonSummary;
    }
}
