package com.mindease.backend.features.habits.dto;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import com.mindease.backend.features.habits.domain.Habit;
import com.mindease.backend.features.habits.domain.HabitRecord;

public record HabitResponse(
        String id,
        String title,
        Integer iconCodePoint,
        Long colorValue,
        String goalLabel,
        String unit,
        int streak,
        boolean doneToday,
        List<Boolean> week,
        boolean active) {

    public static HabitResponse from(Habit habit, List<HabitRecord> recentRecords,
                                     boolean doneToday, int streak) {
        LocalDate today = LocalDate.now();
        List<Boolean> week = new ArrayList<>();

        for (int i = 6; i >= 0; i--) {
            LocalDate date = today.minusDays(i);
            boolean completed = recentRecords.stream()
                    .anyMatch(r -> r.getDate().equals(date) && r.isCompleted());
            week.add(completed);
        }

        return new HabitResponse(
                habit.getId(),
                habit.getTitle(),
                habit.getIconCodePoint(),
                habit.getColorValue(),
                habit.getGoalLabel(),
                habit.getUnit(),
                streak,
                doneToday,
                week,
                habit.isActive());
    }
}
