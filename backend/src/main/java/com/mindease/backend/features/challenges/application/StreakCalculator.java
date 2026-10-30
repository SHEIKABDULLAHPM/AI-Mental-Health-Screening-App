package com.mindease.backend.features.challenges.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.List;

/**
 * Computes meaningful daily streaks from a list of activity dates (local dates).
 *
 * <p>Rules:</p>
 * <ul>
 *   <li>First activity → streak 1.</li>
 *   <li>Consecutive local calendar days → streak increments.</li>
 *   <li>Same-day duplicates do not multiply the streak.</li>
 *   <li>A missed day resets the streak to 1 on the next activity.</li>
 *   <li>Month/year boundaries are handled naturally via LocalDate math.</li>
 * </ul>
 */
public final class StreakCalculator {

    private StreakCalculator() {
    }

    /**
     * Compute the current streak ending today (or the most recent activity if
     * none is today), given distinct activity local-dates.
     */
    public static int current(List<LocalDate> activityDates, ZoneId zone) {
        List<LocalDate> distinct = activityDates.stream()
                .distinct()
                .sorted()
                .toList();
        if (distinct.isEmpty()) {
            return 0;
        }
        LocalDate mostRecent = distinct.get(distinct.size() - 1);
        LocalDate today = LocalDate.now(zone);

        // If the most recent activity is not today and not yesterday, the streak
        // would have already reset — report 0 for a broken streak.
        long gapDays = ChronoUnit.DAYS.between(mostRecent, today);
        if (gapDays > 1) {
            return 0;
        }

        int streak = 1;
        LocalDate cursor = mostRecent;
        for (int i = distinct.size() - 2; i >= 0; i--) {
            LocalDate d = distinct.get(i);
            if (d.equals(cursor.minusDays(1))) {
                streak++;
                cursor = d;
            } else {
                break;
            }
        }
        return streak;
    }

    /**
     * Return the list of distinct local dates from instants.
     */
    public static List<LocalDate> toDates(List<Instant> instants, ZoneId zone) {
        return instants.stream()
                .map(i -> i.atZone(zone).toLocalDate())
                .distinct()
                .sorted()
                .toList();
    }

    // For the StreakCalculator test: convenience.
    public static LocalDate toDate(Instant instant, ZoneId zone) {
        return instant.atZone(zone).toLocalDate();
    }
}
