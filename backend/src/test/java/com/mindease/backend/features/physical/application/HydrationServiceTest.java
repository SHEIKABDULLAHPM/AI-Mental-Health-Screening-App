package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.HydrationEntry;
import com.mindease.backend.features.physical.domain.HydrationEntryRepository;
import com.mindease.backend.features.physical.domain.WellnessGoal;
import com.mindease.backend.features.physical.domain.WellnessGoalRepository;
import com.mindease.backend.features.physical.dto.HydrationDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Hydration totals are always the sum of the surviving entries, so edits and
 * deletions correct every number immediately. A day with no entries is absent,
 * never a fabricated zero.
 */
@ExtendWith(MockitoExtension.class)
class HydrationServiceTest {

    private static final String USER = "user-a";
    private static final String NOW = "UTC";

    @Mock
    private HydrationEntryRepository entries;
    @Mock
    private WellnessGoalRepository goals;

    private HydrationService service;

    @BeforeEach
    void setUp() {
        UserTimeZoneHolder.set(NOW);
        service = new HydrationService(entries, goals, new LifestyleUnits());
        lenient().when(entries.save(any(HydrationEntry.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @AfterEach
    void tearDown() {
        UserTimeZoneHolder.clear();
    }

    private HydrationEntry entry(String id, LocalDate date, double ml, Instant at) {
        HydrationEntry row = new HydrationEntry();
        row.setId(id);
        row.setUserId(USER);
        row.setDate(date);
        row.setAmountMl(ml);
        row.setTimestamp(at);
        return row;
    }

    @Test
    void add_normalisesUnitAndStoresUserEnteredSource() {
        LocalDate today = LocalDate.now(java.time.ZoneOffset.UTC);
        when(entries.findByUserIdAndDateOrderByTimestampAsc(USER, today)).thenReturn(List.of());

        var response = service.add(USER, new HydrationDtos.HydrationRequest(0.5d, "l", null));

        ArgumentCaptor<HydrationEntry> saved = ArgumentCaptor.forClass(HydrationEntry.class);
        verify(entries).save(saved.capture());
        assertThat(saved.getValue().getAmountMl()).isEqualTo(500d);
        assertThat(saved.getValue().getUserId()).isEqualTo(USER);
        assertThat(saved.getValue().getDate()).isEqualTo(today);
        assertThat(saved.getValue().getSource().name()).isEqualTo("USER_ENTERED");
        assertThat(response.amountMl()).isEqualTo(500d);
    }

    @Test
    void add_rejectsFutureTimestampAndUnknownUnit() {
        assertThatThrownBy(() -> service.add(USER, new HydrationDtos.HydrationRequest(
                200d, "ml", Instant.now().plus(1, ChronoUnit.HOURS))))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);

        assertThatThrownBy(() -> service.add(USER, new HydrationDtos.HydrationRequest(
                200d, "bucket", null)))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void add_rejectsDailyTotalAboveSafetyCeiling() {
        LocalDate today = LocalDate.now(java.time.ZoneOffset.UTC);
        when(entries.findByUserIdAndDateOrderByTimestampAsc(USER, today))
                .thenReturn(List.of(entry("e1", today, 14_000d, Instant.now())));

        assertThatThrownBy(() -> service.add(USER, new HydrationDtos.HydrationRequest(
                2000d, "ml", null)))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("15000");
        verify(entries, never()).save(any(HydrationEntry.class));
    }

    @Test
    void update_rewritesTotalsAndEnforcesOwnership() {
        LocalDate today = LocalDate.now(java.time.ZoneOffset.UTC);
        HydrationEntry existing = entry("e1", today, 300d, Instant.now());
        when(entries.findByIdAndUserId("e1", USER)).thenReturn(Optional.of(existing));
        when(entries.findByUserIdAndDateOrderByTimestampAsc(USER, today))
                .thenReturn(List.of(existing));

        var updated = service.update(USER, "e1",
                new HydrationDtos.HydrationRequest(750d, "ml", Instant.now()));

        assertThat(updated.amountMl()).isEqualTo(750d);
        assertThat(existing.getAmountMl()).isEqualTo(750d);
    }

    @Test
    void update_ofAnotherUsersEntryIsNotFound() {
        when(entries.findByIdAndUserId("e9", USER)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.update(USER, "e9",
                new HydrationDtos.HydrationRequest(200d, "ml", null)))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
        verify(entries, never()).save(any(HydrationEntry.class));
    }

    @Test
    void delete_enforcesOwnership() {
        when(entries.findByIdAndUserId("e1", USER)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.delete(USER, "e1"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
        verify(entries, never()).delete(any(HydrationEntry.class));
    }

    @Test
    void overview_sumsSurvivingEntriesAndOmitsEmptyDays() {
        LocalDate today = LocalDate.now(java.time.ZoneOffset.UTC);
        LocalDate yesterday = today.minusDays(1);
        when(goals.findByUserId(USER)).thenReturn(Optional.empty());
        when(entries.findByUserIdAndDateBetweenOrderByDateDesc(eq(USER), any(), eq(today)))
                .thenReturn(List.of(
                        entry("e1", today, 250d, Instant.now()),
                        entry("e2", today, 500d, Instant.now().plusSeconds(60)),
                        entry("e3", yesterday, 1000d, Instant.now().minusSeconds(86_400))));

        var response = service.overview(USER, 7);

        assertThat(response.targetMl()).isEqualTo(2000);
        assertThat(response.targetCustomized()).isFalse();
        assertThat(response.today().totalMl()).isEqualTo(750d);
        assertThat(response.today().entryCount()).isEqualTo(2);
        // yesterday is present; the five days with no entries are absent.
        assertThat(response.days()).hasSize(2);
        assertThat(response.days())
                .allSatisfy(day -> assertThat(day.totalMl()).isGreaterThan(0d));
        assertThat(response.guidance()).containsIgnoringCase("vary");
    }

    @Test
    void overview_respectsCustomTargetAndReportsIt() {
        LocalDate today = LocalDate.now(java.time.ZoneOffset.UTC);
        WellnessGoal goal = new WellnessGoal();
        goal.setUserId(USER);
        goal.setDailyHydrationMl(2800);
        when(goals.findByUserId(USER)).thenReturn(Optional.of(goal));
        when(entries.findByUserIdAndDateBetweenOrderByDateDesc(eq(USER), any(), eq(today)))
                .thenReturn(List.of());

        var response = service.overview(USER, null);

        assertThat(response.targetMl()).isEqualTo(2800);
        assertThat(response.targetCustomized()).isTrue();
        assertThat(response.today().totalMl()).isZero();
        assertThat(response.today().entryCount()).isZero();
    }

    @Test
    void todayTotal_isNullWhenNothingLogged() {
        LocalDate today = LocalDate.now(java.time.ZoneOffset.UTC);
        when(entries.findByUserIdAndDateOrderByTimestampAsc(USER, today)).thenReturn(List.of());

        assertThat(service.todayTotalMl(USER, today)).isNull();
    }

    @Test
    void updateTarget_persistsOnlyThatField() {
        WellnessGoal existing = new WellnessGoal();
        existing.setUserId(USER);
        existing.setDailySteps(8000);
        when(goals.findByUserId(USER)).thenReturn(Optional.of(existing));
        when(entries.findByUserIdAndDateBetweenOrderByDateDesc(anyString(), any(), any()))
                .thenReturn(List.of());

        service.updateTarget(USER, 2600);

        assertThat(existing.getDailyHydrationMl()).isEqualTo(2600);
        assertThat(existing.getDailySteps()).isEqualTo(8000);
    }
}
