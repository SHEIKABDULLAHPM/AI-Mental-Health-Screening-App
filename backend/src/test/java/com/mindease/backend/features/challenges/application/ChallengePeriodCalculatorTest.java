package com.mindease.backend.features.challenges.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.ZoneId;

import org.junit.jupiter.api.Test;

import com.mindease.backend.features.challenges.domain.ChallengeFrequency;

class ChallengePeriodCalculatorTest {

    private static final ZoneId UTC = ZoneId.of("UTC");

    @Test
    void dailyPeriodKeyIsLocalDate() {
        Instant instant = Instant.parse("2026-08-28T14:30:00Z");
        assertThat(ChallengePeriodCalculator.periodKey(instant, ChallengeFrequency.DAILY, UTC))
                .isEqualTo("2026-08-28");
    }

    @Test
    void dailyPeriodBoundaries() {
        Instant instant = Instant.parse("2026-08-28T14:30:00Z");
        Instant start = ChallengePeriodCalculator.periodStart(instant, ChallengeFrequency.DAILY, UTC);
        assertThat(start).isEqualTo(Instant.parse("2026-08-28T00:00:00Z"));
        Instant end = ChallengePeriodCalculator.periodEnd(start, ChallengeFrequency.DAILY, UTC);
        assertThat(end).isEqualTo(Instant.parse("2026-08-29T00:00:00Z"));
    }

    @Test
    void weeklyPeriodKeyIsMonday() {
        // 2026-08-28 is a Friday → weekly period starts Monday 2026-08-24.
        Instant instant = Instant.parse("2026-08-28T14:30:00Z");
        assertThat(ChallengePeriodCalculator.periodKey(instant, ChallengeFrequency.WEEKLY, UTC))
                .isEqualTo("2026-08-24");
    }

    @Test
    void weeklyPeriodKeyMondayStaysSameDay() {
        // 2026-08-24 is a Monday.
        Instant instant = Instant.parse("2026-08-24T10:00:00Z");
        assertThat(ChallengePeriodCalculator.periodKey(instant, ChallengeFrequency.WEEKLY, UTC))
                .isEqualTo("2026-08-24");
    }

    @Test
    void weeklyPeriodBoundaries() {
        Instant instant = Instant.parse("2026-08-28T14:30:00Z");
        Instant start = ChallengePeriodCalculator.periodStart(instant, ChallengeFrequency.WEEKLY, UTC);
        assertThat(start).isEqualTo(Instant.parse("2026-08-24T00:00:00Z"));
        Instant end = ChallengePeriodCalculator.periodEnd(start, ChallengeFrequency.WEEKLY, UTC);
        assertThat(end).isEqualTo(Instant.parse("2026-08-31T00:00:00Z"));
    }

    @Test
    void monthlyBoundaryFallsInSameWeek() {
        // A date late in a month: 2026-08-31 is a Monday → week starts 2026-08-31.
        Instant instant = Instant.parse("2026-08-31T12:00:00Z");
        assertThat(ChallengePeriodCalculator.periodKey(instant, ChallengeFrequency.WEEKLY, UTC))
                .isEqualTo("2026-08-31");
    }

    @Test
    void unknownZoneFallsBackToUtc() {
        assertThat(ChallengePeriodCalculator.zone("Not/AZone")).isEqualTo(UTC);
    }
}
