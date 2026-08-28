package com.mindease.backend.features.habits.domain;

import java.time.Instant;
import java.time.LocalDate;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "habit_records")
@CompoundIndex(name = "user_habit_date", def = "{'userId': 1, 'habitId': 1, 'date': 1}", unique = true)
public class HabitRecord {

    @Id
    private String id;

    @Indexed
    private String userId;

    @Indexed
    private String habitId;

    private LocalDate date;

    private boolean completed;

    private Instant createdAt;

    public HabitRecord() {
    }

    public HabitRecord(String userId, String habitId, LocalDate date, boolean completed) {
        this.userId = userId;
        this.habitId = habitId;
        this.date = date;
        this.completed = completed;
        this.createdAt = Instant.now();
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

    public String getHabitId() {
        return habitId;
    }

    public void setHabitId(String habitId) {
        this.habitId = habitId;
    }

    public LocalDate getDate() {
        return date;
    }

    public void setDate(LocalDate date) {
        this.date = date;
    }

    public boolean isCompleted() {
        return completed;
    }

    public void setCompleted(boolean completed) {
        this.completed = completed;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}
