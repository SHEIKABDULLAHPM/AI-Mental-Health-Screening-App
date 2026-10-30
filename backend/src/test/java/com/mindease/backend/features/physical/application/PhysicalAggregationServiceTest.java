package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;

import org.junit.jupiter.api.Test;

import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.SleepSession;

class PhysicalAggregationServiceTest {

    private final PhysicalAggregationService service = new PhysicalAggregationService();
    private final LocalDate today = LocalDate.of(2026, 10, 6);

    private DailyActivity day(LocalDate date, Integer steps, Double distance, Double calories) {
        DailyActivity activity = new DailyActivity();
        activity.setDate(date);
        activity.setSteps(steps);
        activity.setDistanceMeters(distance);
        activity.setCaloriesKcal(calories);
        return activity;
    }

    @Test
    void weekly_allNullData_yieldsNoDataNotZeros() {
        var summary = service.weeklyActivity(List.of(
                day(today, null, null, null),
                day(today.minusDays(1), null, null, null)), today);

        assertThat(summary.daysWithData()).isZero();
        assertThat(summary.totalSteps()).isNull();
        assertThat(summary.averageSteps()).isNull();
        assertThat(summary.totalDistanceMeters()).isNull();
        assertThat(summary.totalCaloriesKcal()).isNull();
        assertThat(summary.bestStepDay()).isNull();
    }

    @Test
    void weekly_averagesOnlyOverDaysThatHaveSteps() {
        var summary = service.weeklyActivity(List.of(
                day(today, 1000, null, null),
                day(today.minusDays(1), null, null, null), // no data day: skipped, not zero
                day(today.minusDays(2), 3000, null, null)), today);

        assertThat(summary.totalSteps()).isEqualTo(4000);
        assertThat(summary.averageSteps()).isEqualTo(2000d); // 4000 / 2 step-days
        assertThat(summary.daysWithData()).isEqualTo(2);
        assertThat(summary.bestStepDay()).isEqualTo(3000);
        assertThat(summary.bestStepDate()).isEqualTo(today.minusDays(2));
    }

    @Test
    void weekly_ignoresDaysOutsideWindow() {
        var summary = service.weeklyActivity(List.of(
                day(today.minusDays(30), 99999, null, null),
                day(today, 500, null, null)), today);

        assertThat(summary.totalSteps()).isEqualTo(500);
        assertThat(summary.daysWithData()).isEqualTo(1);
    }

    @Test
    void weekly_periodSpansSevenDays() {
        var summary = service.weeklyActivity(List.of(), today);

        assertThat(summary.periodStart()).isEqualTo(today.minusDays(6));
        assertThat(summary.periodEnd()).isEqualTo(today);
    }

    @Test
    void weeklySleep_noSessions_reportsZeroSessionsAndNullAverage() {
        var summary = service.weeklySleep(List.of(), today, today.minusDays(6));

        assertThat(summary.sessionsWithData()).isZero();
        assertThat(summary.totalDurationMillis()).isNull();
        assertThat(summary.averageDurationMillis()).isNull();
    }

    @Test
    void weeklySleep_averagesAcrossSessions() {
        SleepSession first = session(today, 6 * 3600_000L);
        SleepSession second = session(today.minusDays(1), 8 * 3600_000L);

        var summary = service.weeklySleep(List.of(first, second), today, today.minusDays(6));

        assertThat(summary.sessionsWithData()).isEqualTo(2);
        assertThat(summary.totalDurationMillis()).isEqualTo(14 * 3600_000L);
        assertThat(summary.averageDurationMillis()).isEqualTo(7 * 3600_000L);
    }

    @Test
    void weeklySleep_outsideTheRequestedWindow_isExcluded() {
        // A session waking the day before the window start is not counted,
        // even though the query had to fetch it (it started a day earlier).
        SleepSession earlier = session(today.minusDays(7), 8 * 3600_000L);

        var summary = service.weeklySleep(List.of(earlier), today, today.minusDays(6));

        assertThat(summary.sessionsWithData()).isZero();
    }

    @Test
    void average_ofEmptyOrNullSample_isNull() {
        assertThat(service.average(List.of())).isNull();
        assertThat(service.average(null)).isNull();
    }

    @Test
    void average_computesMean() {
        assertThat(service.average(List.of(70.0, 80.0, 90.0))).isEqualTo(80.0);
    }

    private SleepSession session(LocalDate date, long durationMillis) {
        SleepSession session = new SleepSession();
        session.setDate(date);
        session.setDurationMillis(durationMillis);
        session.setStartTime(LocalDateTime.of(date, java.time.LocalTime.of(23, 0))
                .toInstant(ZoneOffset.UTC));
        return session;
    }
}
