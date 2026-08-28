package com.mindease.backend.features.checkin.domain;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "daily_checkins")
@CompoundIndex(name = "user_date", def = "{'userId': 1, 'date': 1}", unique = true)
public class DailyCheckin {

    @Id
    private String id;

    @Indexed
    private String userId;

    private LocalDate date;

    private Integer mood;

    private Integer sleep;

    private Integer energy;

    private Integer stress;

    private List<String> activities;

    private Instant createdAt;

    private Instant updatedAt;

    public DailyCheckin() {
    }

    public DailyCheckin(String userId, LocalDate date, Integer mood, Integer sleep,
                        Integer energy, Integer stress, List<String> activities) {
        this.userId = userId;
        this.date = date;
        this.mood = mood;
        this.sleep = sleep;
        this.energy = energy;
        this.stress = stress;
        this.activities = activities;
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

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public Integer getMood() {
        return mood;
    }

    public void setMood(Integer mood) {
        this.mood = mood;
    }

    public Integer getSleep() {
        return sleep;
    }

    public void setSleep(Integer sleep) {
        this.sleep = sleep;
    }

    public Integer getEnergy() {
        return energy;
    }

    public void setEnergy(Integer energy) {
        this.energy = energy;
    }

    public Integer getStress() {
        return stress;
    }

    public void setStress(Integer stress) {
        this.stress = stress;
    }

    public List<String> getActivities() {
        return activities;
    }

    public void setActivities(List<String> activities) {
        this.activities = activities;
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
