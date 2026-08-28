package com.mindease.backend.features.habits.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "habits")
public class Habit {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String title;

    private Integer iconCodePoint;

    private Long colorValue;

    private String goalLabel;

    private String unit;

    private boolean active;

    private Instant createdAt;

    private Instant updatedAt;

    public Habit() {
    }

    public Habit(String userId, String title, Integer iconCodePoint, Long colorValue,
                 String goalLabel, String unit) {
        this.userId = userId;
        this.title = title;
        this.iconCodePoint = iconCodePoint;
        this.colorValue = colorValue;
        this.goalLabel = goalLabel;
        this.unit = unit;
        this.active = true;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
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

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public Integer getIconCodePoint() {
        return iconCodePoint;
    }

    public void setIconCodePoint(Integer iconCodePoint) {
        this.iconCodePoint = iconCodePoint;
    }

    public Long getColorValue() {
        return colorValue;
    }

    public void setColorValue(Long colorValue) {
        this.colorValue = colorValue;
    }

    public String getGoalLabel() {
        return goalLabel;
    }

    public void setGoalLabel(String goalLabel) {
        this.goalLabel = goalLabel;
    }

    public String getUnit() {
        return unit;
    }

    public void setUnit(String unit) {
        this.unit = unit;
    }

    public boolean isActive() {
        return active;
    }

    public void setActive(boolean active) {
        this.active = active;
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
