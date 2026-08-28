package com.mindease.backend.features.habits.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.habits.domain.Habit;
import com.mindease.backend.features.habits.domain.HabitRecord;
import com.mindease.backend.features.habits.domain.HabitRecordRepository;
import com.mindease.backend.features.habits.domain.HabitRepository;
import com.mindease.backend.features.habits.dto.CreateHabitRequest;
import com.mindease.backend.features.habits.dto.HabitRecordRequest;
import com.mindease.backend.features.habits.dto.HabitResponse;
import com.mindease.backend.features.habits.dto.UpdateHabitRequest;

@ExtendWith(MockitoExtension.class)
class HabitServiceTest {

    @Mock
    private HabitRepository habitRepository;

    @Mock
    private HabitRecordRepository recordRepository;

    private HabitService service;

    private static final String USER_ID = "user-1";
    private static final String OTHER_USER_ID = "user-2";
    private static final String HABIT_ID = "habit-1";
    private static final String RECORD_ID = "record-1";

    @BeforeEach
    void setUp() {
        service = new HabitService(habitRepository, recordRepository);
    }

    // --------------------------------------------------------- createHabit

    @Test
    void createHabitSuccessfully() {
        CreateHabitRequest request = new CreateHabitRequest(
                "Meditate", 0x1F6CC, 0xFF0000L, "10 min daily", "minutes");
        Habit saved = buildHabit(HABIT_ID, USER_ID, "Meditate");
        when(habitRepository.save(any())).thenReturn(saved);
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(eq(USER_ID), any()))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(eq(USER_ID), any(), any()))
                .thenReturn(Optional.empty());

        HabitResponse response = service.createHabit(USER_ID, request);

        assertThat(response.title()).isEqualTo("Meditate");
        assertThat(response.goalLabel()).isEqualTo("10 min daily");
        assertThat(response.unit()).isEqualTo("minutes");

        ArgumentCaptor<Habit> captor = ArgumentCaptor.forClass(Habit.class);
        verify(habitRepository).save(captor.capture());
        Habit captured = captor.getValue();
        assertThat(captured.getUserId()).isEqualTo(USER_ID);
        assertThat(captured.getTitle()).isEqualTo("Meditate");
        assertThat(captured.getIconCodePoint()).isEqualTo(0x1F6CC);
        assertThat(captured.getColorValue()).isEqualTo(0xFF0000);
        assertThat(captured.isActive()).isTrue();
        assertThat(captured.getCreatedAt()).isNotNull();
    }

    @Test
    void createHabitDefaultsUnitToSessionWhenNull() {
        CreateHabitRequest request = new CreateHabitRequest(
                "Exercise", null, null, "Daily workout", null);
        Habit saved = buildHabit(HABIT_ID, USER_ID, "Exercise");
        when(habitRepository.save(any())).thenReturn(saved);
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(eq(USER_ID), any()))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(eq(USER_ID), any(), any()))
                .thenReturn(Optional.empty());

        HabitResponse response = service.createHabit(USER_ID, request);

        assertThat(response.unit()).isEqualTo("session");

        ArgumentCaptor<Habit> captor = ArgumentCaptor.forClass(Habit.class);
        verify(habitRepository).save(captor.capture());
        assertThat(captor.getValue().getUnit()).isEqualTo("session");
    }

    // --------------------------------------------------------- getUserHabits

    @Test
    void getUserHabitsReturnsActiveHabits() {
        Habit habit1 = buildHabit(HABIT_ID, USER_ID, "Meditate");
        Habit habit2 = buildHabit("habit-2", USER_ID, "Exercise");
        when(habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(USER_ID))
                .thenReturn(List.of(habit1, habit2));
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, HABIT_ID, LocalDate.now()))
                .thenReturn(Optional.empty());
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, "habit-2"))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, "habit-2", LocalDate.now()))
                .thenReturn(Optional.empty());

        List<HabitResponse> habits = service.getUserHabits(USER_ID);

        assertThat(habits).hasSize(2);
        assertThat(habits.get(0).title()).isEqualTo("Meditate");
        assertThat(habits.get(1).title()).isEqualTo("Exercise");
    }

    @Test
    void getUserHabitsReturnsEmptyListWhenNoneExist() {
        when(habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(USER_ID))
                .thenReturn(Collections.emptyList());

        List<HabitResponse> habits = service.getUserHabits(USER_ID);

        assertThat(habits).isEmpty();
    }

    // --------------------------------------------------------- getHabitById

    @Test
    void getHabitByIdReturnsOwnedHabit() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Meditate");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, HABIT_ID, LocalDate.now()))
                .thenReturn(Optional.empty());

        HabitResponse response = service.getHabitById(USER_ID, HABIT_ID);

        assertThat(response.id()).isEqualTo(HABIT_ID);
        assertThat(response.title()).isEqualTo("Meditate");
    }

    @Test
    void getHabitByIdThrowsNotFoundForOtherUsersHabit() {
        Habit habit = buildHabit(HABIT_ID, OTHER_USER_ID, "Their Habit");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        assertThatThrownBy(() -> service.getHabitById(USER_ID, HABIT_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void getHabitByIdThrowsNotFoundForNonExistentHabit() {
        when(habitRepository.findById("missing-id")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getHabitById(USER_ID, "missing-id"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- updateHabit

    @Test
    void updateHabitSuccessfully() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Old Title");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));
        when(habitRepository.save(any())).thenReturn(habit);
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, HABIT_ID, LocalDate.now()))
                .thenReturn(Optional.empty());

        UpdateHabitRequest request = new UpdateHabitRequest(
                "New Title", 0x1F601, null, "New Goal", null);
        HabitResponse response = service.updateHabit(USER_ID, HABIT_ID, request);

        assertThat(response.title()).isEqualTo("New Title");
        assertThat(response.iconCodePoint()).isEqualTo(0x1F601);
        assertThat(response.goalLabel()).isEqualTo("New Goal");

        ArgumentCaptor<Habit> captor = ArgumentCaptor.forClass(Habit.class);
        verify(habitRepository).save(captor.capture());
        assertThat(captor.getValue().getTitle()).isEqualTo("New Title");
        assertThat(captor.getValue().getUpdatedAt()).isNotNull();
    }

    @Test
    void updateHabitThrowsNotFoundForOtherUsersHabit() {
        Habit habit = buildHabit(HABIT_ID, OTHER_USER_ID, "Their Habit");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        UpdateHabitRequest request = new UpdateHabitRequest("Hacked", null, null, null, null);
        assertThatThrownBy(() -> service.updateHabit(USER_ID, HABIT_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(habitRepository, never()).save(any());
    }

    // --------------------------------------------------------- deleteHabit

    @Test
    void deleteHabitSoftDeletes() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Meditate");
        habit.setActive(true);
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        service.deleteHabit(USER_ID, HABIT_ID);

        ArgumentCaptor<Habit> captor = ArgumentCaptor.forClass(Habit.class);
        verify(habitRepository).save(captor.capture());
        assertThat(captor.getValue().isActive()).isFalse();
        assertThat(captor.getValue().getUpdatedAt()).isNotNull();
    }

    @Test
    void deleteHabitThrowsNotFoundForOtherUsersHabit() {
        Habit habit = buildHabit(HABIT_ID, OTHER_USER_ID, "Their Habit");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        assertThatThrownBy(() -> service.deleteHabit(USER_ID, HABIT_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(habitRepository, never()).save(any());
    }

    // --------------------------------------------------------- recordCompletion

    @Test
    void recordCompletionCreatesRecord() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Meditate");
        LocalDate today = LocalDate.now();
        HabitRecordRequest request = new HabitRecordRequest(today, true);

        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, HABIT_ID, today))
                .thenReturn(Optional.empty());
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(Collections.emptyList());

        HabitResponse response = service.recordCompletion(USER_ID, HABIT_ID, request);

        assertThat(response.id()).isEqualTo(HABIT_ID);

        ArgumentCaptor<HabitRecord> captor = ArgumentCaptor.forClass(HabitRecord.class);
        verify(recordRepository).save(captor.capture());
        HabitRecord captured = captor.getValue();
        assertThat(captured.getUserId()).isEqualTo(USER_ID);
        assertThat(captured.getHabitId()).isEqualTo(HABIT_ID);
        assertThat(captured.getDate()).isEqualTo(today);
        assertThat(captured.isCompleted()).isTrue();
    }

    @Test
    void recordCompletionIdempotentForSameDate() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Meditate");
        LocalDate today = LocalDate.now();
        HabitRecord existing = buildRecord(RECORD_ID, USER_ID, HABIT_ID, today, false);
        HabitRecordRequest request = new HabitRecordRequest(today, true);

        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, HABIT_ID, today))
                .thenReturn(Optional.of(existing));
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(List.of(existing));

        HabitResponse response = service.recordCompletion(USER_ID, HABIT_ID, request);

        assertThat(response.id()).isEqualTo(HABIT_ID);
        verify(recordRepository).save(existing);
        assertThat(existing.isCompleted()).isTrue();
    }

    @Test
    void recordCompletionThrowsNotFoundForOtherUsersHabit() {
        Habit habit = buildHabit(HABIT_ID, OTHER_USER_ID, "Their Habit");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        HabitRecordRequest request = new HabitRecordRequest(LocalDate.now(), true);
        assertThatThrownBy(() -> service.recordCompletion(USER_ID, HABIT_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- getHabitHistory

    @Test
    void getHabitHistoryReturnsPaginatedRecords() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Meditate");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        LocalDate today = LocalDate.now();
        HabitRecord r1 = buildRecord("r1", USER_ID, HABIT_ID, today, true);
        HabitRecord r2 = buildRecord("r2", USER_ID, HABIT_ID, today.minusDays(1), true);
        HabitRecord r3 = buildRecord("r3", USER_ID, HABIT_ID, today.minusDays(2), false);
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(List.of(r1, r2, r3));

        List<HabitRecord> page1 = service.getHabitHistory(USER_ID, HABIT_ID, 0, 2);
        assertThat(page1).hasSize(2);
        assertThat(page1.get(0).getDate()).isEqualTo(today);
        assertThat(page1.get(1).getDate()).isEqualTo(today.minusDays(1));

        List<HabitRecord> page2 = service.getHabitHistory(USER_ID, HABIT_ID, 1, 2);
        assertThat(page2).hasSize(1);
        assertThat(page2.get(0).getDate()).isEqualTo(today.minusDays(2));
    }

    @Test
    void getHabitHistoryReturnsEmptyWhenNoRecords() {
        Habit habit = buildHabit(HABIT_ID, USER_ID, "Meditate");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(Collections.emptyList());

        List<HabitRecord> history = service.getHabitHistory(USER_ID, HABIT_ID, 0, 10);

        assertThat(history).isEmpty();
    }

    @Test
    void getHabitHistoryThrowsNotFoundForOtherUsersHabit() {
        Habit habit = buildHabit(HABIT_ID, OTHER_USER_ID, "Their Habit");
        when(habitRepository.findById(HABIT_ID)).thenReturn(Optional.of(habit));

        assertThatThrownBy(() -> service.getHabitHistory(USER_ID, HABIT_ID, 0, 10))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- getWeeklyProgress

    @Test
    void getWeeklyProgressReturnsHabitData() {
        Habit habit1 = buildHabit(HABIT_ID, USER_ID, "Meditate");
        Habit habit2 = buildHabit("habit-2", USER_ID, "Exercise");
        when(habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(USER_ID))
                .thenReturn(List.of(habit1, habit2));
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, HABIT_ID))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, HABIT_ID, LocalDate.now()))
                .thenReturn(Optional.empty());
        when(recordRepository.findByUserIdAndHabitIdOrderByDateDesc(USER_ID, "habit-2"))
                .thenReturn(Collections.emptyList());
        when(recordRepository.findByUserIdAndHabitIdAndDate(USER_ID, "habit-2", LocalDate.now()))
                .thenReturn(Optional.empty());

        List<HabitResponse> progress = service.getWeeklyProgress(USER_ID);

        assertThat(progress).hasSize(2);
        assertThat(progress.get(0).id()).isEqualTo(HABIT_ID);
        assertThat(progress.get(0).week()).hasSize(7);
        assertThat(progress.get(1).id()).isEqualTo("habit-2");
    }

    @Test
    void getWeeklyProgressReturnsEmptyWhenNoHabits() {
        when(habitRepository.findByUserIdAndActiveTrueOrderByCreatedAtDesc(USER_ID))
                .thenReturn(Collections.emptyList());

        List<HabitResponse> progress = service.getWeeklyProgress(USER_ID);

        assertThat(progress).isEmpty();
    }

    // --------------------------------------------------------- helpers

    private static Habit buildHabit(String id, String userId, String title) {
        Habit habit = new Habit(userId, title, 0x1F6CC, 0xFF0000L, "Goal", "session");
        habit.setId(id);
        return habit;
    }

    private static HabitRecord buildRecord(String id, String userId, String habitId,
                                           LocalDate date, boolean completed) {
        HabitRecord record = new HabitRecord(userId, habitId, date, completed);
        record.setId(id);
        return record;
    }
}
