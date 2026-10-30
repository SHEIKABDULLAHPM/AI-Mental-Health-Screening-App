package com.mindease.backend.features.physical.application;

import java.time.LocalDate;
import java.util.List;

import org.springframework.stereotype.Service;

import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.SleepSession;

/**
 * Converts raw/normalized physical data into daily and weekly summaries.
 *
 * <p>Aggregates are computed from data that actually exists — days without
 * records are excluded from averages instead of contributing zeros, and every
 * aggregate reports how many days it was derived from so consumers never
 * mistake "no data" for "zero".</p>
 */
@Service
public class PhysicalAggregationService {

    public record WeeklyActivitySummary(
            LocalDate periodStart,
            LocalDate periodEnd,
            int daysWithData,
            Integer totalSteps,
            Double averageSteps,
            Double totalDistanceMeters,
            Double totalCaloriesKcal,
            Integer bestStepDay,
            LocalDate bestStepDate) {
    }

    public record WeeklySleepSummary(
            int sessionsWithData,
            Long totalDurationMillis,
            Long averageDurationMillis) {
    }

    /**
     * Weekly activity totals from daily rows (null fields mean no data for
     * that day and are skipped, never counted as zero).
     */
    public WeeklyActivitySummary weeklyActivity(List<DailyActivity> days, LocalDate today) {
        LocalDate start = today.minusDays(6);
        int daysWithData = 0;
        int stepDays = 0;
        int distanceDays = 0;
        int calorieDays = 0;
        double steps = 0;
        double distance = 0;
        double calories = 0;
        int bestSteps = -1;
        LocalDate bestDate = null;

        for (DailyActivity day : days) {
            if (day.getDate() == null || day.getDate().isBefore(start) || day.getDate().isAfter(today)) {
                continue;
            }
            boolean counted = false;
            if (day.getSteps() != null) {
                steps += day.getSteps();
                stepDays++;
                counted = true;
                if (day.getSteps() > bestSteps) {
                    bestSteps = day.getSteps();
                    bestDate = day.getDate();
                }
            }
            if (day.getDistanceMeters() != null) {
                distance += day.getDistanceMeters();
                distanceDays++;
                counted = true;
            }
            if (day.getCaloriesKcal() != null) {
                calories += day.getCaloriesKcal();
                calorieDays++;
                counted = true;
            }
            if (counted) {
                daysWithData++;
            }
        }

        return new WeeklyActivitySummary(
                start,
                today,
                daysWithData,
                stepDays == 0 ? null : (int) steps,
                stepDays == 0 ? null : steps / stepDays,
                distanceDays == 0 ? null : distance,
                calorieDays == 0 ? null : calories,
                bestSteps < 0 ? null : bestSteps,
                bestDate);
    }

    /** Weekly sleep totals keyed by wake day within the requested period. */
    public WeeklySleepSummary weeklySleep(List<SleepSession> sessions, LocalDate today,
                                          LocalDate wakeFrom) {
        LocalDate start = wakeFrom;
        int count = 0;
        long total = 0;
        for (SleepSession session : sessions) {
            if (session.getDate() == null || session.getDate().isBefore(start)
                    || session.getDate().isAfter(today)) {
                continue;
            }
            if (session.getDurationMillis() == null) {
                continue;
            }
            count++;
            total += session.getDurationMillis();
        }
        return new WeeklySleepSummary(count, count == 0 ? null : total,
                count == 0 ? null : total / count);
    }

    /** Arithmetic mean of a non-empty sample, or null for an empty sample. */
    public Double average(List<Double> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        double sum = 0;
        for (Double value : values) {
            if (value != null) {
                sum += value;
            }
        }
        return sum / values.size();
    }
}
