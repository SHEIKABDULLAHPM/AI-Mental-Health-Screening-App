package com.mindease.backend.features.futureletters.application;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.futureletters.domain.FutureLetter;
import com.mindease.backend.features.futureletters.domain.FutureLetterRepository;
import com.mindease.backend.features.futureletters.dto.CreateLetterRequest;
import com.mindease.backend.features.futureletters.dto.LetterResponse;
import com.mindease.backend.features.futureletters.dto.UpdateLetterRequest;

@Service
public class FutureLetterService {

    private static final Set<String> VALID_STATUSES = Set.of("scheduled", "delivered", "opened");

    private final FutureLetterRepository repository;

    public FutureLetterService(FutureLetterRepository repository) {
        this.repository = repository;
    }

    public LetterResponse createLetter(String userId, CreateLetterRequest request) {
        FutureLetter letter = new FutureLetter();
        letter.setUserId(userId);
        letter.setTitle(request.title());
        letter.setRecipient(request.recipient() != null ? request.recipient() : "Future me");
        letter.setContent(request.content());
        letter.setScheduledDate(request.scheduledDate());
        letter.setStatus("scheduled");
        letter.setCreatedAt(Instant.now());
        letter.setUpdatedAt(Instant.now());

        return LetterResponse.from(repository.save(letter));
    }

    public List<LetterResponse> getUserLetters(String userId) {
        return repository.findByUserIdOrderByScheduledDateAsc(userId)
                .stream()
                .map(LetterResponse::from)
                .toList();
    }

    public LetterResponse getLetterById(String userId, String id) {
        FutureLetter letter = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Future letter not found"));
        return LetterResponse.from(letter);
    }

    public LetterResponse updateLetter(String userId, String id, UpdateLetterRequest request) {
        FutureLetter letter = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Future letter not found"));

        if (!"scheduled".equals(letter.getStatus())) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Can only update letters with scheduled status");
        }

        if (request.title() != null) {
            letter.setTitle(request.title());
        }
        if (request.recipient() != null) {
            letter.setRecipient(request.recipient());
        }
        if (request.content() != null) {
            letter.setContent(request.content());
        }
        if (request.scheduledDate() != null) {
            if (!request.scheduledDate().isAfter(LocalDate.now())) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Scheduled date must be in the future");
            }
            letter.setScheduledDate(request.scheduledDate());
        }
        letter.setUpdatedAt(Instant.now());

        return LetterResponse.from(repository.save(letter));
    }

    public void deleteLetter(String userId, String id) {
        FutureLetter letter = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Future letter not found"));
        repository.delete(letter);
    }

    public List<LetterResponse> getScheduledLetters(String userId) {
        return repository.findByUserIdAndStatusOrderByScheduledDateAsc(userId, "scheduled")
                .stream()
                .map(LetterResponse::from)
                .toList();
    }

    public List<LetterResponse> getDeliveredLetters(String userId) {
        LocalDate today = LocalDate.now();

        // Auto-transition scheduled letters whose date has passed to delivered.
        List<FutureLetter> overdue = repository
                .findByUserIdAndScheduledDateBeforeAndStatusOrderByScheduledDateAsc(
                        userId, today, "scheduled");
        for (FutureLetter letter : overdue) {
            letter.setStatus("delivered");
            letter.setUpdatedAt(Instant.now());
            repository.save(letter);
        }

        // Fetch all delivered and opened letters.
        List<FutureLetter> delivered = repository
                .findByUserIdAndStatusOrderByScheduledDateAsc(userId, "delivered");
        List<FutureLetter> opened = repository.findByUserIdAndStatusOrderByScheduledDateAsc(
                userId, "opened");

        java.util.List<FutureLetter> all = new java.util.ArrayList<>(delivered);
        all.addAll(opened);

        return all.stream()
                .map(LetterResponse::from)
                .toList();
    }

    public LetterResponse markAsOpened(String userId, String id) {
        FutureLetter letter = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Future letter not found"));

        String status = letter.getStatus();

        // Allow opening delivered letters directly.
        // For scheduled letters whose date has passed, auto-transition to opened.
        if ("opened".equals(status)) {
            // Already opened — return as-is.
            return LetterResponse.from(letter);
        } else if ("delivered".equals(status)) {
            letter.setStatus("opened");
        } else if ("scheduled".equals(status)) {
            // Only allow if the scheduled date is in the past.
            LocalDate scheduledDate = letter.getScheduledDate();
            if (scheduledDate == null || scheduledDate.isAfter(LocalDate.now())) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "This letter hasn't been delivered yet.");
            }
            letter.setStatus("opened");
        } else {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Cannot open a letter with status: " + status);
        }

        letter.setUpdatedAt(Instant.now());
        return LetterResponse.from(repository.save(letter));
    }
}
