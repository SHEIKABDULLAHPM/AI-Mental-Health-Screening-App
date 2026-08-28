package com.mindease.backend.features.futureletters.application;

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
import com.mindease.backend.features.futureletters.domain.FutureLetter;
import com.mindease.backend.features.futureletters.domain.FutureLetterRepository;
import com.mindease.backend.features.futureletters.dto.CreateLetterRequest;
import com.mindease.backend.features.futureletters.dto.LetterResponse;
import com.mindease.backend.features.futureletters.dto.UpdateLetterRequest;

@ExtendWith(MockitoExtension.class)
class FutureLetterServiceTest {

    @Mock
    private FutureLetterRepository repository;

    private FutureLetterService service;

    private static final String USER_ID = "user-1";
    private static final String OTHER_USER_ID = "user-2";
    private static final String LETTER_ID = "letter-1";

    @BeforeEach
    void setUp() {
        service = new FutureLetterService(repository);
    }

    // --------------------------------------------------------- createLetter

    @Test
    void createLetterSuccessfully() {
        CreateLetterRequest request = new CreateLetterRequest(
                "Dear Future Me", "Myself", "You are doing great!", LocalDate.now().plusDays(90));
        FutureLetter saved = buildLetter(LETTER_ID, USER_ID, "Dear Future Me", "scheduled");
        saved.setRecipient("Myself");
        saved.setContent("You are doing great!");
        when(repository.save(any())).thenReturn(saved);

        LetterResponse response = service.createLetter(USER_ID, request);

        assertThat(response.id()).isEqualTo(LETTER_ID);
        assertThat(response.title()).isEqualTo("Dear Future Me");
        assertThat(response.recipient()).isEqualTo("Myself");
        assertThat(response.content()).isEqualTo("You are doing great!");
        assertThat(response.status()).isEqualTo("scheduled");
        assertThat(response.createdAt()).isNotNull();
        assertThat(response.updatedAt()).isNotNull();

        ArgumentCaptor<FutureLetter> captor = ArgumentCaptor.forClass(FutureLetter.class);
        verify(repository).save(captor.capture());
        FutureLetter captured = captor.getValue();
        assertThat(captured.getUserId()).isEqualTo(USER_ID);
        assertThat(captured.getTitle()).isEqualTo("Dear Future Me");
        assertThat(captured.getRecipient()).isEqualTo("Myself");
        assertThat(captured.getStatus()).isEqualTo("scheduled");
    }

    @Test
    void createLetterDefaultsRecipientToFutureMe() {
        CreateLetterRequest request = new CreateLetterRequest(
                "Hello", null, "Content", LocalDate.now().plusDays(30));
        FutureLetter saved = buildLetter(LETTER_ID, USER_ID, "Hello", "scheduled");
        when(repository.save(any())).thenReturn(saved);

        service.createLetter(USER_ID, request);

        ArgumentCaptor<FutureLetter> captor = ArgumentCaptor.forClass(FutureLetter.class);
        verify(repository).save(captor.capture());
        assertThat(captor.getValue().getRecipient()).isEqualTo("Future me");
    }

    // --------------------------------------------------------- getUserLetters

    @Test
    void getUserLettersReturnsAllLetters() {
        FutureLetter l1 = buildLetter(LETTER_ID, USER_ID, "Letter 1", "scheduled");
        FutureLetter l2 = buildLetter("letter-2", USER_ID, "Letter 2", "delivered");
        when(repository.findByUserIdOrderByScheduledDateAsc(USER_ID))
                .thenReturn(List.of(l1, l2));

        List<LetterResponse> letters = service.getUserLetters(USER_ID);

        assertThat(letters).hasSize(2);
        assertThat(letters.get(0).id()).isEqualTo(LETTER_ID);
        assertThat(letters.get(1).id()).isEqualTo("letter-2");
    }

    @Test
    void getUserLettersReturnsEmptyWhenNoneExist() {
        when(repository.findByUserIdOrderByScheduledDateAsc(USER_ID))
                .thenReturn(Collections.emptyList());

        List<LetterResponse> letters = service.getUserLetters(USER_ID);

        assertThat(letters).isEmpty();
    }

    // --------------------------------------------------------- getLetterById

    @Test
    void getLetterByIdReturnsOwnedLetter() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "My Letter", "scheduled");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        LetterResponse response = service.getLetterById(USER_ID, LETTER_ID);

        assertThat(response.id()).isEqualTo(LETTER_ID);
        assertThat(response.title()).isEqualTo("My Letter");
        assertThat(response.status()).isEqualTo("scheduled");
    }

    @Test
    void getLetterByIdThrowsNotFoundForOtherUsersLetter() {
        when(repository.findByIdAndUserId(LETTER_ID, OTHER_USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getLetterById(OTHER_USER_ID, LETTER_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void getLetterByIdThrowsNotFoundForNonExistentLetter() {
        when(repository.findByIdAndUserId("missing-id", USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getLetterById(USER_ID, "missing-id"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- updateLetter

    @Test
    void updateLetterSuccessfully() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Old Title", "scheduled");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));
        when(repository.save(any())).thenReturn(letter);

        UpdateLetterRequest request = new UpdateLetterRequest(
                "New Title", "New Recipient", "New content", null);
        LetterResponse response = service.updateLetter(USER_ID, LETTER_ID, request);

        assertThat(response.title()).isEqualTo("New Title");

        ArgumentCaptor<FutureLetter> captor = ArgumentCaptor.forClass(FutureLetter.class);
        verify(repository).save(captor.capture());
        FutureLetter captured = captor.getValue();
        assertThat(captured.getTitle()).isEqualTo("New Title");
        assertThat(captured.getRecipient()).isEqualTo("New Recipient");
        assertThat(captured.getContent()).isEqualTo("New content");
        assertThat(captured.getUpdatedAt()).isNotNull();
    }

    @Test
    void updateLetterWithScheduledDateInFuture() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "scheduled");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));
        when(repository.save(any())).thenReturn(letter);

        LocalDate futureDate = LocalDate.now().plusDays(60);
        UpdateLetterRequest request = new UpdateLetterRequest(
                null, null, null, futureDate);
        service.updateLetter(USER_ID, LETTER_ID, request);

        ArgumentCaptor<FutureLetter> captor = ArgumentCaptor.forClass(FutureLetter.class);
        verify(repository).save(captor.capture());
        assertThat(captor.getValue().getScheduledDate()).isEqualTo(futureDate);
    }

    @Test
    void updateLetterRejectsUpdateWhenNotScheduled() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "delivered");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        UpdateLetterRequest request = new UpdateLetterRequest(
                "Hacked", null, null, null);
        assertThatThrownBy(() -> service.updateLetter(USER_ID, LETTER_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);

        verify(repository, never()).save(any());
    }

    @Test
    void updateLetterRejectsUpdateWhenOpened() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "opened");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        UpdateLetterRequest request = new UpdateLetterRequest(
                "Hacked", null, null, null);
        assertThatThrownBy(() -> service.updateLetter(USER_ID, LETTER_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);

        verify(repository, never()).save(any());
    }

    @Test
    void updateLetterRejectsScheduledDateInPast() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "scheduled");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        UpdateLetterRequest request = new UpdateLetterRequest(
                null, null, null, LocalDate.now().minusDays(5));
        assertThatThrownBy(() -> service.updateLetter(USER_ID, LETTER_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);

        verify(repository, never()).save(any());
    }

    @Test
    void updateLetterThrowsNotFoundForOtherUsersLetter() {
        when(repository.findByIdAndUserId(LETTER_ID, OTHER_USER_ID))
                .thenReturn(Optional.empty());

        UpdateLetterRequest request = new UpdateLetterRequest(
                "Hacked", null, null, null);
        assertThatThrownBy(() -> service.updateLetter(OTHER_USER_ID, LETTER_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- deleteLetter

    @Test
    void deleteLetterSuccessfully() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "To Delete", "scheduled");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        service.deleteLetter(USER_ID, LETTER_ID);

        verify(repository).delete(letter);
    }

    @Test
    void deleteLetterThrowsNotFoundForOtherUsersLetter() {
        when(repository.findByIdAndUserId(LETTER_ID, OTHER_USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteLetter(OTHER_USER_ID, LETTER_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);

        verify(repository, never()).delete(any());
    }

    // --------------------------------------------------------- getScheduledLetters

    @Test
    void getScheduledLettersReturnsScheduledOnly() {
        FutureLetter l1 = buildLetter(LETTER_ID, USER_ID, "Scheduled 1", "scheduled");
        FutureLetter l2 = buildLetter("letter-2", USER_ID, "Scheduled 2", "scheduled");
        when(repository.findByUserIdAndStatusOrderByScheduledDateAsc(USER_ID, "scheduled"))
                .thenReturn(List.of(l1, l2));

        List<LetterResponse> letters = service.getScheduledLetters(USER_ID);

        assertThat(letters).hasSize(2);
        assertThat(letters.get(0).status()).isEqualTo("scheduled");
        assertThat(letters.get(1).status()).isEqualTo("scheduled");
    }

    @Test
    void getScheduledLettersReturnsEmptyWhenNoneScheduled() {
        when(repository.findByUserIdAndStatusOrderByScheduledDateAsc(USER_ID, "scheduled"))
                .thenReturn(Collections.emptyList());

        List<LetterResponse> letters = service.getScheduledLetters(USER_ID);

        assertThat(letters).isEmpty();
    }

    // --------------------------------------------------------- getDeliveredLetters

    @Test
    void getDeliveredLettersReturnsDeliveredAndOpened() {
        FutureLetter delivered = buildLetter(LETTER_ID, USER_ID, "Delivered", "delivered");
        FutureLetter opened = buildLetter("letter-2", USER_ID, "Opened", "opened");

        when(repository.findByUserIdAndScheduledDateBeforeAndStatusOrderByScheduledDateAsc(
                eq(USER_ID), any(LocalDate.class), eq("scheduled")))
                .thenReturn(List.of(delivered));
        when(repository.findByUserIdAndStatusOrderByScheduledDateAsc(USER_ID, "opened"))
                .thenReturn(List.of(opened));

        List<LetterResponse> letters = service.getDeliveredLetters(USER_ID);

        assertThat(letters).hasSize(2);
        assertThat(letters.get(0).id()).isEqualTo(LETTER_ID);
        assertThat(letters.get(1).id()).isEqualTo("letter-2");
    }

    @Test
    void getDeliveredLettersReturnsEmptyWhenNoneDelivered() {
        when(repository.findByUserIdAndScheduledDateBeforeAndStatusOrderByScheduledDateAsc(
                eq(USER_ID), any(LocalDate.class), eq("scheduled")))
                .thenReturn(Collections.emptyList());
        when(repository.findByUserIdAndStatusOrderByScheduledDateAsc(USER_ID, "opened"))
                .thenReturn(Collections.emptyList());

        List<LetterResponse> letters = service.getDeliveredLetters(USER_ID);

        assertThat(letters).isEmpty();
    }

    // --------------------------------------------------------- markAsOpened

    @Test
    void markAsOpenedTransitionsDeliveredToOpened() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "delivered");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));
        when(repository.save(any())).thenReturn(letter);

        LetterResponse response = service.markAsOpened(USER_ID, LETTER_ID);

        assertThat(response.status()).isEqualTo("opened");

        ArgumentCaptor<FutureLetter> captor = ArgumentCaptor.forClass(FutureLetter.class);
        verify(repository).save(captor.capture());
        assertThat(captor.getValue().getStatus()).isEqualTo("opened");
        assertThat(captor.getValue().getUpdatedAt()).isNotNull();
    }

    @Test
    void markAsOpenedRejectsIfNotDelivered() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "scheduled");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        assertThatThrownBy(() -> service.markAsOpened(USER_ID, LETTER_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);

        verify(repository, never()).save(any());
    }

    @Test
    void markAsOpenedRejectsIfAlreadyOpened() {
        FutureLetter letter = buildLetter(LETTER_ID, USER_ID, "Title", "opened");
        when(repository.findByIdAndUserId(LETTER_ID, USER_ID))
                .thenReturn(Optional.of(letter));

        assertThatThrownBy(() -> service.markAsOpened(USER_ID, LETTER_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);
    }

    @Test
    void markAsOpenedThrowsNotFoundForOtherUsersLetter() {
        when(repository.findByIdAndUserId(LETTER_ID, OTHER_USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.markAsOpened(OTHER_USER_ID, LETTER_ID))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------- helpers

    private static FutureLetter buildLetter(String id, String userId, String title, String status) {
        FutureLetter letter = new FutureLetter();
        letter.setId(id);
        letter.setUserId(userId);
        letter.setTitle(title);
        letter.setRecipient("Future me");
        letter.setContent("Content for " + title);
        letter.setScheduledDate(LocalDate.now().plusDays(90));
        letter.setStatus(status);
        letter.setCreatedAt(Instant.now());
        letter.setUpdatedAt(Instant.now());
        return letter;
    }
}
