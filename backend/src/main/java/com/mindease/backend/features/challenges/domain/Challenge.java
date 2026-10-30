package com.mindease.backend.features.challenges.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Controlled challenge definition (catalog). A Challenge is a template:
 * it defines what activity it tracks, how often it repeats, and what counts as
 * completion. Per-user progress lives in {@link UserChallenge}.
 *
 * <p>Definitions come only from the managed catalog/seed — never from an LLM or
 * an unbounded client request.</p>
 */
@Document(collection = "challenges")
public class Challenge {

    @Id
    private String id;

    private String title;

    private String description;

    /** Why this challenge may be useful (supportive, non-clinical). */
    private String why;

    /**
     * Controlled activity-backed type. See {@link ChallengeType}.
     * Never trust a free-form string from the client.
     */
    private String type;

    /** How often the challenge repeats. See {@link ChallengeFrequency}. */
    private String frequency;

    /**
     * Number of verified activities required to complete one instance of the
     * challenge. For a DAILY challenge this is normally 1.
     */
    private int target;

    /** Organizing category (e.g. Focus, Memory, Reflection, Relaxation, Mindfulness, Daily Wellness). */
    private String category;

    /** Difficulty level: easy, medium, hard. */
    private String difficulty;

    /** Estimated duration label (e.g. "5 min", "10 min"). */
    private String estimatedDuration;

    /** Legacy "days" hint preserved for compatibility with existing UI/records. */
    private int durationDays;

    /** Reward points awarded on completion. */
    private int points;

    /** Reward label (e.g. "Mood Consistency Badge"). */
    private String reward;

    /** Badge code unlocked on completion (deterministic). */
    private String badgeCode;

    /** Simple eligibility rule expression that must match a user signal. */
    private String eligibilityRule;

    /** Available within the environment. */
    @Indexed
    private boolean active;

    /** Update challenge definition version (for cache busting / API parity). */
    private int version;

    private Instant createdAt;
    private Instant updatedAt;

    public Challenge() {
    }

    // ── Getters / Setters ───────────────────────────────────────────

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getWhy() { return why; }
    public void setWhy(String why) { this.why = why; }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public String getFrequency() { return frequency; }
    public void setFrequency(String frequency) { this.frequency = frequency; }

    public int getTarget() { return target; }
    public void setTarget(int target) { this.target = target; }

    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }

    public String getDifficulty() { return difficulty; }
    public void setDifficulty(String difficulty) { this.difficulty = difficulty; }

    public String getEstimatedDuration() { return estimatedDuration; }
    public void setEstimatedDuration(String estimatedDuration) { this.estimatedDuration = estimatedDuration; }

    public int getDurationDays() { return durationDays; }
    public void setDurationDays(int durationDays) { this.durationDays = durationDays; }

    public int getPoints() { return points; }
    public void setPoints(int points) { this.points = points; }

    public String getReward() { return reward; }
    public void setReward(String reward) { this.reward = reward; }

    public String getBadgeCode() { return badgeCode; }
    public void setBadgeCode(String badgeCode) { this.badgeCode = badgeCode; }

    public String getEligibilityRule() { return eligibilityRule; }
    public void setEligibilityRule(String eligibilityRule) { this.eligibilityRule = eligibilityRule; }

    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }

    public int getVersion() { return version; }
    public void setVersion(int version) { this.version = version; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
