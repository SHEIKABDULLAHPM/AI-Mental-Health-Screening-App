package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.features.physical.domain.DailyActivity;
import com.mindease.backend.features.physical.domain.DailyActivityRepository;
import com.mindease.backend.features.physical.domain.HealthReadingRepository;
import com.mindease.backend.features.physical.domain.SleepSessionRepository;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Trends are a faithful projection of stored records. Missing days stay
 * missing: no interpolation, no zero filling, and the coverage counters expose
 * exactly how much of the window is real.
 */
@ExtendWith(MockitoExtension.class)
class PhysicalTrendServiceTest {

    private static final String USER = "user-a";
    private static final LocalDate TODAY = LocalDate.now(ZoneOffset.UTC);

    @Mock
    private DailyActivityRepository dailyActivity;
    @Mock
    private SleepSessionRepository sleepSessions;
    @Mock
    private HealthReadingRepository readings;
    @Mock
    private HydrationService hydration;

    private PhysicalTrendService service;

    @BeforeEach
    void setUp() {
        UserTimeZoneHolder.set("UTC");
        service = new PhysicalTrendService(dailyActivity, sleepSessions, readings, hydration);
        lenient().when(dailyActivity
                        .findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(sleepSessions
                        .findByUserIdAndStartTimeBetweenOrderByStartTimeDesc(any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(readings
                        .findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc(
                                any(), any(), any(), any()))
                .thenReturn(List.of());
        lenient().when(hydration.todayTotalMl(eq(USER), any())).thenReturn(null);
    }

    @AfterEach
    void tearDown() {
        UserTimeZoneHolder.clear();
    }

    private DailyActivity activity(LocalDate date, Integer steps, Double distance,
                                   Double calories, Integer activeMinutes) {
        DailyActivity row = new DailyActivity();
        row.setUserId(USER);
        row.setDate(date);
        row.setSteps(steps);
        row.setDistanceMeters(distance);
        row.setCaloriesKcal(calories);
        row.setActiveMinutes(activeMinutes);
        row.setUpdatedAt(Instant.now());
        return row;
    }

    @Test
    void trends_containsOnlyDaysWithRecords() {
        when(dailyActivity.findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of(
                        activity(TODAY, 8000, 6000d, 300d, 40),
                        activity(TODAY.minusDays(3), 4000, 3000d, 150d, 20)));

        var response = service.trends(USER, 7);
        var steps = response.metrics().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(response.windowDays()).isEqualTo(7);
        assertThat(steps.points()).hasSize(2);
        assertThat(steps.points()).extracting(point -> point.date())
                .containsExactly(TODAY.minusDays(3), TODAY);
        assertThat(steps.daysWithData()).isEqualTo(2);
        assertThat(steps.windowDays()).isEqualTo(7);
        assertThat(response.coverageNotes())
                .anyMatch(note -> note.contains("Steps: 2 of 7 days"));
        assertThat(response.coverageNotes())
                .anyMatch(note -> note.contains("not estimated"));
    }

    @Test
    void trends_compareAgainstTheUsersPreviousWindow() {
        // Previous window: 6 days ago .. 12 days ago. One 4000-step day there.
        when(dailyActivity.findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of(activity(TODAY, 6000, 4500d, 250d, 30)))
                .thenReturn(List.of(activity(TODAY.minusDays(8), 4000, 3000d, 150d, 20)));

        var response = service.trends(USER, 7);
        var steps = response.metrics().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.average()).isEqualTo(6000d);
        assertThat(steps.previousAverage()).isEqualTo(4000d);
        assertThat(steps.changePercent()).isEqualTo(50d);
    }

    @Test
    void trends_doNotInventZeroForMissingActivity() {
        when(dailyActivity.findByUserIdAndDateBetweenOrderByDateDesc(any(), any(), any()))
                .thenReturn(List.of());

        var response = service.trends(USER, 7);
        var steps = response.metrics().stream()
                .filter(item -> "steps".equals(item.metric())).findFirst().orElseThrow();

        assertThat(steps.points()).isEmpty();
        assertThat(steps.average()).isNull();
        assertThat(steps.daysWithData()).isZero();
        assertThat(response.coverageNotes())
                .anyMatch(note -> note.startsWith("Steps: no data"));
    }

    @Test
    void trends_hydrationUsesLoggedTotalsOnly() {
        when(hydration.todayTotalMl(eq(USER), eq(TODAY))).thenReturn(1500d);

        var response = service.trends(USER, 7);
        var water = response.metrics().stream()
                .filter(item -> "hydrationMl".equals(item.metric())).findFirst().orElseThrow();

        assertThat(water.points()).hasSize(1);
        assertThat(water.points().get(0).value()).isEqualTo(1500d);
        assertThat(water.quality()).isEqualTo("USER_ENTERED");
    }

    @Test
    void trends_windowIsClampedToSupportedRange() {
        var wide = service.trends(USER, 10_000);
        var narrow = service.trends(USER, 0);
        var fallback = service.trends(USER, null);

        assertThat(wide.windowDays()).isEqualTo(90);
        assertThat(narrow.windowDays()).isEqualTo(1);
        assertThat(fallback.windowDays()).isEqualTo(7);
    }

    @Test
    void trends_includeAdvancedMetricsAsEmptySeriesWhenUnavailable() {
        var response = service.trends(USER, 7);

        var hrv = response.metrics().stream()
                .filter(item -> "hrv".equals(item.metric())).findFirst().orElseThrow();
        var spo2 = response.metrics().stream()
                .filter(item -> "spo2".equals(item.metric())).findFirst().orElseThrow();

        assertThat(hrv.points()).isEmpty();
        assertThat(hrv.note()).containsIgnoringCase("Only present");
        assertThat(spo2.points()).isEmpty();
        assertThat(spo2.note()).doesNotContainIgnoringCase("healthy");
    }
}
