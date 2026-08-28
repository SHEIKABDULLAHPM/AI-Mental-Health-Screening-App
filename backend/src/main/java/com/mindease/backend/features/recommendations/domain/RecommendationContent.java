package com.mindease.backend.features.recommendations.domain;

import java.time.Instant;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A piece of recommended wellness content.
 * Content must be approved and active before it can be recommended.
 */
@Document(collection = "recommendation_content")
@CompoundIndex(name = "category_active_idx", def = "{'category': 1, 'active': 1}")
public class RecommendationContent {

    @Id
    private String id;

    private String title;
    private String description;

    @Indexed
    private String category; // meditation, exercises, articles, videos, music, sounds, personalized

    private String type; // guided, exercise, article, video, audio, ambient, routine

    private String duration; // "5 min", "10 min", etc.

    private String difficulty; // easy, medium, challenging

    private String contentReference; // route or deep link in the app

    private List<String> tags; // stress, anxiety, sleep, focus, energy, etc.

    private List<String> eligibilityTags; // mood-based eligibility

    private List<String> safetyTags; // safety classification tags

    @Indexed
    private boolean active;

    private int contentVersion;

    private Instant createdAt;
    private Instant updatedAt;

    public RecommendationContent() {}

    // Getters and setters
    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public String getDuration() { return duration; }
    public void setDuration(String duration) { this.duration = duration; }

    public String getDifficulty() { return difficulty; }
    public void setDifficulty(String difficulty) { this.difficulty = difficulty; }

    public String getContentReference() { return contentReference; }
    public void setContentReference(String contentReference) { this.contentReference = contentReference; }

    public List<String> getTags() { return tags; }
    public void setTags(List<String> tags) { this.tags = tags; }

    public List<String> getEligibilityTags() { return eligibilityTags; }
    public void setEligibilityTags(List<String> eligibilityTags) { this.eligibilityTags = eligibilityTags; }

    public List<String> getSafetyTags() { return safetyTags; }
    public void setSafetyTags(List<String> safetyTags) { this.safetyTags = safetyTags; }

    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }

    public int getContentVersion() { return contentVersion; }
    public void setContentVersion(int contentVersion) { this.contentVersion = contentVersion; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
