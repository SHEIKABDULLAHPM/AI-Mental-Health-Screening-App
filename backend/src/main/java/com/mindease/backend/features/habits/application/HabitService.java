package com.mindease.backend.features.habits.application;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.habits.domain.Habit;
import com.mindease.backend.features.habits.domain.HabitRecord;
import com.mindease.backend.features.habits.domain.HabitRecordRepository;
import com.mindease.backend.features.habits.domain.HabitRepository;
import com.mindease.backend.features.habits.dto.CreateHabitRequest;
import com.mindease.backend.features.habits.dto.HabitRecordRequest;
import com.mindease.backend.features.habits.dto.HabitResponse;
import com.mindease.backend.features.habits.dto.UpdateHabitRequest;

@Service
public class HabitService {

    private final HabitRepository habitRepository;
    private final HabitRecordRepository recordRepository;

    public HabitService(HabitRepository habitRepository, HabitRecordRepository recordRepository) {
        this.habitRepository = habitRepository;
        this.recordRepository = recordRepository;
    }

    public HabitResponse createHabit(String userId, CreateHabitRequest request) {
        String unit = request.unit() != null ? request.unit() : "session";

        Habit habit = new Habit(
                userId,
                request.title(),
                request.iconCodePoint(),
                request.colorValue(),
                request.goalLabel(),
                unit);

        habitRepository.save(habit);
        return buildHabitResponse(habit, userId);
    }

    public List<HabitResponse> getUserHabits(String userId) {
        List<Habit> habits = habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(userId);
        return habits.stream()
                .map(h -> buildHabitResponse(h, userId))
                .toList();
    }

    public HabitResponse getHabitById(String userId, String habitId) {
        Habit habit = findHabitWithOwnership(habitId, userId);
        return buildHabitResponse(habit, userId);
    }

    public HabitResponse updateHabit(String userId, String habitId, UpdateHabitRequest request) {
        Habit habit = findHabitWithOwnership(habitId, userId);

        if (request.title() != null) {
            habit.setTitle(request.title());
        }
        if (request.iconCodePoint() != null) {
            habit.setIconCodePoint(request.iconCodePoint());
        }
        if (request.colorValue() != null) {
            habit.setColorValue(request.colorValue());
        }
        if (request.goalLabel() != null) {
            habit.setGoalLabel(request.goalLabel());
        }
        if (request.unit() != null) {
            habit.setUnit(request.unit());
        }
        habit.setUpdatedAt(Instant.now());

        habitRepository.save(habit);
        return buildHabitResponse(habit, userId);
    }

    public void deleteHabit(String userId, String habitId) {
        Habit habit = findHabitWithOwnership(habitId, userId);
        habit.setActive(false);
        habit.setUpdatedAt(Instant.now());
        habitRepository.save(habit);
    }

    public HabitResponse recordCompletion(String userId, String habitId, HabitRecordRequest request) {
        Habit habit = findHabitWithOwnership(habitId, userId);

        Optional<HabitRecord> existing = recordRepository
                .findByUserIdAndHabitIdAndDate(userId, habitId, request.date());

        if (existing.isPresent()) {
            existing.get().setCompleted(request.completed());
            recordRepository.save(existing.get());
        } else {
            HabitRecord record = new HabitRecord(userId, habitId, request.date(), request.completed());
            recordRepository.save(record);
        }

        return buildHabitResponse(habit, userId);
    }

    public List<HabitRecord> getHabitHistory(String userId, String habitId, int page, int size) {
        findHabitWithOwnership(habitId, userId);

        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "date"));
        return recordRepository.findByUserIdAndHabitIdOrderByDateDesc(userId, habitId)
                .stream()
                .skip((long) page * size)
                .limit(size)
                .toList();
    }

    public List<HabitResponse> getWeeklyProgress(String userId) {
        List<Habit> habits = habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(userId);
        return habits.stream()
                .map(h -> buildHabitResponse(h, userId))
                .toList();
    }

    public List<HabitResponse> getMonthlyProgress(String userId) {
        List<Habit> habits = habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(userId);
        return habits.stream()
                .map(h -> buildHabitResponse(h, userId))
                .toList();
    }

    private Habit findHabitWithOwnership(String habitId, String userId) {
        Habit habit = habitRepository.findById(habitId)
                .orElseThrow(() -> ApiException.notFound("Habit not found"));
        if (!habit.getUserId().equals(userId)) {
            throw ApiException.notFound("Habit not found");
        }
        return habit;
    }

    private HabitResponse buildHabitResponse(Habit habit, String userId) {
        LocalDate today = LocalDate.now();
        LocalDate weekStart = today.minusDays(6);

        List<HabitRecord> recentRecords = recordRepository
                .findByUserIdAndHabitIdOrderByDateDesc(userId, habit.getId())
                .stream()
                .filter(r -> !r.getDate().isBefore(weekStart))
                .toList();

        boolean doneToday = recordRepository
                .findByUserIdAndHabitIdAndDate(userId, habit.getId(), today)
                .map(HabitRecord::isCompleted)
                .orElse(false);

        int streak = calculateStreak(userId, habit.getId());

        return HabitResponse.from(habit, recentRecords, doneToday, streak);
    }

    private int calculateStreak(String userId, String habitId) {
        LocalDate today = LocalDate.now();
        int streak = 0;
        LocalDate checkDate = today;

        while (true) {
            Optional<HabitRecord> record = recordRepository
                    .findByUserIdAndHabitIdAndDate(userId, habitId, checkDate);

            if (record.isPresent() && record.get().isCompleted()) {
                streak++;
                checkDate = checkDate.minusDays(1);
            } else {
                break;
            }
        }

        return streak;
    }
}
