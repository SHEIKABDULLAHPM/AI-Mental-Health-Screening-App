package com.mindease.backend.features.checkin.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.checkin.domain.DailyCheckin;
import com.mindease.backend.features.checkin.domain.DailyCheckinRepository;
import com.mindease.backend.features.checkin.dto.CheckinResponse;
import com.mindease.backend.features.checkin.dto.CreateCheckinRequest;
import com.mindease.backend.features.checkin.dto.UpdateCheckinRequest;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;

@ExtendWith(MockitoExtension.class)
class DailyCheckinServiceTest {

    @Mock
    private DailyCheckinRepository repository;

    private DailyCheckinService service;

    private static final String USER_ID = "user-1";
    private static final String CHECKIN_ID = "checkin-1";
    private static final String OTHER_USER_ID = "other-user";

    @BeforeEach
    void setUp() {
        service = new DailyCheckinService(repository);
    }

    // --------------------------------------------------------------- createCheckin

    @Test
    void createCheckinSuccessfully() {
        CreateCheckinRequest request = new CreateCheckinRequest(4, 3, 5, 2, List.of("exercise", "reading"));
        when(repository.findByUserIdAndDate(USER_ID, LocalDate.now())).thenReturn(Optional.empty());

        CheckinResponse response = service.createCheckin(USER_ID, request);

        assertThat(response.mood()).isEqualTo(4);
        assertThat(response.sleep()).isEqualTo(3);
        assertThat(response.energy()).isEqualTo(5);
        assertThat(response.stress()).isEqualTo(2);
        assertThat(response.activities()).containsExactly("exercise", "reading");
        verify(repository).save(any(DailyCheckin.class));
    }

    @Test
    void createCheckinDuplicateDateRejection() {
        CreateCheckinRequest request = new CreateCheckinRequest(3, 3, 3, 3, List.of("meditation"));
        DailyCheckin existing = createEntity("existing-1", USER_ID, LocalDate.now());
        when(repository.findByUserIdAndDate(USER_ID, LocalDate.now())).thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.createCheckin(USER_ID, request))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.CONFLICT);
                    assertThat(ex.getMessage()).contains("already exists");
                });
        verify(repository, never()).save(any());
    }

    // --------------------------------------------------------------- getTodayCheckin

    @Test
    void getTodayCheckinReturnsTodaysCheckin() {
        DailyCheckin checkin = createEntity(CHECKIN_ID, USER_ID, LocalDate.now());
        checkin.setMood(5);
        when(repository.findByUserIdAndDate(USER_ID, LocalDate.now())).thenReturn(Optional.of(checkin));

        CheckinResponse response = service.getTodayCheckin(USER_ID);

        assertThat(response).isNotNull();
        assertThat(response.id()).isEqualTo(CHECKIN_ID);
        assertThat(response.mood()).isEqualTo(5);
    }

    @Test
    void getTodayCheckinReturnsNullWhenNoneExists() {
        when(repository.findByUserIdAndDate(USER_ID, LocalDate.now())).thenReturn(Optional.empty());

        CheckinResponse response = service.getTodayCheckin(USER_ID);

        assertThat(response).isNull();
    }

    // --------------------------------------------------------------- getCheckinHistory

    @Test
    void getCheckinHistoryPaginated() {
        List<DailyCheckin> checkins = List.of(
                createEntity("c-3", USER_ID, LocalDate.now().minusDays(2)),
                createEntity("c-2", USER_ID, LocalDate.now().minusDays(1)),
                createEntity("c-1", USER_ID, LocalDate.now()));
        when(repository.findByUserIdOrderByDateDesc(eq(USER_ID), any())).thenReturn(checkins);

        List<CheckinResponse> history = service.getCheckinHistory(USER_ID, 0, 10);

        assertThat(history).hasSize(3);
        assertThat(history.get(0).id()).isEqualTo("c-3");
        verify(repository).findByUserIdOrderByDateDesc(eq(USER_ID), any());
    }

    // --------------------------------------------------------------- getCheckinById

    @Test
    void getCheckinByIdWithOwnershipValidation() {
        DailyCheckin checkin = createEntity(CHECKIN_ID, USER_ID, LocalDate.now());
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.of(checkin));

        CheckinResponse response = service.getCheckinById(USER_ID, CHECKIN_ID);

        assertThat(response.id()).isEqualTo(CHECKIN_ID);
        assertThat(response.date()).isEqualTo(LocalDate.now());
    }

    @Test
    void getCheckinByIdThrowsNotFoundForOtherUsersCheckin() {
        DailyCheckin checkin = createEntity(CHECKIN_ID, OTHER_USER_ID, LocalDate.now());
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.of(checkin));

        assertThatThrownBy(() -> service.getCheckinById(USER_ID, CHECKIN_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.FORBIDDEN);
                    assertThat(ex.getMessage()).contains("access");
                });
    }

    @Test
    void getCheckinByIdThrowsNotFoundWhenMissing() {
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getCheckinById(USER_ID, CHECKIN_ID))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------------- updateCheckin

    @Test
    void updateCheckinWithOwnershipValidation() {
        DailyCheckin checkin = createEntity(CHECKIN_ID, USER_ID, LocalDate.now());
        checkin.setMood(3);
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.of(checkin));
        when(repository.save(any())).thenReturn(checkin);

        UpdateCheckinRequest request = new UpdateCheckinRequest(5, null, null, null, null);
        CheckinResponse response = service.updateCheckin(USER_ID, CHECKIN_ID, request);

        assertThat(response.mood()).isEqualTo(5);
        verify(repository).save(any(DailyCheckin.class));
    }

    @Test
    void updateCheckinPartialUpdateOnlySomeFields() {
        DailyCheckin checkin = createEntity(CHECKIN_ID, USER_ID, LocalDate.now());
        checkin.setMood(2);
        checkin.setSleep(4);
        checkin.setEnergy(3);
        checkin.setStress(2);
        checkin.setActivities(List.of("walking"));
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.of(checkin));
        when(repository.save(any())).thenReturn(checkin);

        UpdateCheckinRequest request = new UpdateCheckinRequest(null, 5, null, null, List.of("yoga"));
        CheckinResponse response = service.updateCheckin(USER_ID, CHECKIN_ID, request);

        assertThat(response.mood()).isEqualTo(2);
        assertThat(response.sleep()).isEqualTo(5);
        assertThat(response.energy()).isEqualTo(3);
        assertThat(response.stress()).isEqualTo(2);
        assertThat(response.activities()).containsExactly("yoga");
    }

    @Test
    void updateCheckinRejectsOtherUsersCheckin() {
        DailyCheckin checkin = createEntity(CHECKIN_ID, OTHER_USER_ID, LocalDate.now());
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.of(checkin));

        UpdateCheckinRequest request = new UpdateCheckinRequest(5, null, null, null, null);
        assertThatThrownBy(() -> service.updateCheckin(USER_ID, CHECKIN_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    void updateCheckinThrowsNotFoundWhenMissing() {
        when(repository.findById(CHECKIN_ID)).thenReturn(Optional.empty());

        UpdateCheckinRequest request = new UpdateCheckinRequest(5, null, null, null, null);
        assertThatThrownBy(() -> service.updateCheckin(USER_ID, CHECKIN_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // ----------------------------------------------------------- validateCheckin

    @Test
    void validateCheckinRejectsMoodBelowOne() {
        try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
            Validator validator = factory.getValidator();
            CreateCheckinRequest request = new CreateCheckinRequest(0, 3, 3, 3, List.of("walk"));
            Set<ConstraintViolation<CreateCheckinRequest>> violations = validator.validate(request);
            assertThat(violations).isNotEmpty();
            assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().equals("mood"));
        }
    }

    @Test
    void validateCheckinRejectsMoodAboveFive() {
        try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
            Validator validator = factory.getValidator();
            CreateCheckinRequest request = new CreateCheckinRequest(6, 3, 3, 3, List.of("walk"));
            Set<ConstraintViolation<CreateCheckinRequest>> violations = validator.validate(request);
            assertThat(violations).isNotEmpty();
            assertThat(violations).anyMatch(v -> v.getPropertyPath().toString().equals("mood"));
        }
    }

    @Test
    void validateCheckinAcceptsBoundaryValues() {
        try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
            Validator validator = factory.getValidator();
            CreateCheckinRequest minRequest = new CreateCheckinRequest(1, 1, 1, 1, List.of());
            CreateCheckinRequest maxRequest = new CreateCheckinRequest(5, 5, 5, 5, List.of());
            assertThat(validator.validate(minRequest)).isEmpty();
            assertThat(validator.validate(maxRequest)).isEmpty();
        }
    }

    // --------------------------------------------------------------- helpers

    private static DailyCheckin createEntity(String id, String userId, LocalDate date) {
        DailyCheckin checkin = new DailyCheckin(userId, date, 3, 3, 3, 3, List.of("general"));
        checkin.setId(id);
        checkin.setCreatedAt(Instant.now());
        checkin.setUpdatedAt(Instant.now());
        return checkin;
    }
}
