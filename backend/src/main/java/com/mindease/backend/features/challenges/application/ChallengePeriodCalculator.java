package com.mindease.backend.features.challenges.application;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;

import com.mindease.backend.features.challenges.domain.ChallengeFrequency;

/**
 * Computes period boundaries for daily and weekly challenges in a given
 * timezone. All authoritative time decisions live server-side; the optional user
 * timezone (default UTC) controls which calendar day/week an activity falls in.
 */
public final class ChallengePeriodCalculator {

    private static final ZoneId DEFAULT_ZONE = ZoneId.of("UTC");

    private ChallengePeriodCalculator() {
    }

    /**
     * Return the resolved zone, defaulting to UTC for unknown values.
     */
    public static ZoneId zone(String userZone) {
        if (userZone == null || userZone.isBlank()) {
            return DEFAULT_ZONE;
        }
        try {
            return ZoneId.of(userZone);
        } catch (Exception e) {
            return DEFAULT_ZONE;
        }
    }

    /**
     * The local calendar day (ISO yyyy-MM-dd) for an instant in the given zone.
     */
    public static String localDate(Instant instant, ZoneId zone) {
        return instant.atZone(zone).toLocalDate().toString();
    }

    /**
     * ISO start of the period for a frequency, as an Instant.
     */
    public static Instant periodStart(Instant instant, ChallengeFrequency frequency, ZoneId zone) {
        LocalDate day = instant.atZone(zone).toLocalDate();
        if (frequency == ChallengeFrequency.WEEKLY) {
            day = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        }
        return day.atStartOfDay(zone).toInstant();
    }

    /**
     * Single canonical string key identifying the period (local day for DAILY,
     * local Monday date for WEEKLY).
     */
    public static String periodKey(Instant instant, ChallengeFrequency frequency, ZoneId zone) {
        LocalDate day = instant.atZone(zone).toLocalDate();
        if (frequency == ChallengeFrequency.WEEKLY) {
            day = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        }
        return day.toString();
    }

    /**
     * End of the period (exclusive).
     */
    public static Instant periodEnd(Instant periodStartInstant, ChallengeFrequency frequency, ZoneId zone) {
        LocalDate startDay = periodStartInstant.atZone(zone).toLocalDate();
        LocalDate endDay;
        if (frequency == ChallengeFrequency.WEEKLY) {
            endDay = startDay.plusDays(7);
        } else {
            endDay = startDay.plusDays(1);
        }
        return endDay.atStartOfDay(zone).toInstant();
    }

    /**
     * The local date corresponding to a period-start Instant (used to detect
     * missing-day resets for streaks).
     */
    public static LocalDate startDate(Instant periodStartInstant, ZoneId zone) {
        return periodStartInstant.atZone(zone).toLocalDate();
    }
}
