package com.mindease.backend.features.physical.domain;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Per-user daily wellness targets.
 *
 * <p>Every field is independently nullable: an unset goal means "the user has
 * not chosen a target yet" and is rendered as such, never as a fabricated
 * default that silently implies a recommendation. The service applies a
 * conservative <em>suggested</em> starting point only when the user opts in,
 * and the UI always labels it as adjustable.</p>
 */
@Document(collection = "wellness_goals")
@CompoundIndex(name = "uq_goal_user", def = "{'userId': 1}", unique = true)
public class WellnessGoal {

    @Id
    private String id;

    @Indexed
    private String userId;

    private Integer dailySteps;

    private Integer dailyActiveMinutes;

    private Integer weeklyWorkoutMinutes;

    private Integer dailySleepMinutes;

    /** Canonical unit: millilitres. */
    private Integer dailyHydrationMl;

    /**
     * Provenance per target: metric name to {@code USER} or
     * {@code AI_RECOMMENDED}. Goals created before provenance existed have no
     * entry and are treated as user-entered, never as AI output.
     */
    private Map<String, String> targetSources = new LinkedHashMap<>();

    private Instant createdAt;

    private Instant updatedAt;

    public WellnessGoal() {
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

    public Integer getDailySteps() {
        return dailySteps;
    }

    public void setDailySteps(Integer dailySteps) {
        this.dailySteps = dailySteps;
    }

    public Integer getDailyActiveMinutes() {
        return dailyActiveMinutes;
    }

    public void setDailyActiveMinutes(Integer dailyActiveMinutes) {
        this.dailyActiveMinutes = dailyActiveMinutes;
    }

    public Integer getWeeklyWorkoutMinutes() {
        return weeklyWorkoutMinutes;
    }

    public void setWeeklyWorkoutMinutes(Integer weeklyWorkoutMinutes) {
        this.weeklyWorkoutMinutes = weeklyWorkoutMinutes;
    }

    public Integer getDailySleepMinutes() {
        return dailySleepMinutes;
    }

    public void setDailySleepMinutes(Integer dailySleepMinutes) {
        this.dailySleepMinutes = dailySleepMinutes;
    }

    public Integer getDailyHydrationMl() {
        return dailyHydrationMl;
    }

    public void setDailyHydrationMl(Integer dailyHydrationMl) {
        this.dailyHydrationMl = dailyHydrationMl;
    }

    public Map<String, String> getTargetSources() {
        return targetSources == null ? new LinkedHashMap<>() : targetSources;
    }

    public void setTargetSources(Map<String, String> targetSources) {
        this.targetSources = targetSources == null ? new LinkedHashMap<>() : targetSources;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }
}
