package com.mindease.backend.features.futureletters.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface FutureLetterRepository extends MongoRepository<FutureLetter, String> {

    List<FutureLetter> findByUserIdOrderByScheduledDateAsc(String userId);

    Optional<FutureLetter> findByIdAndUserId(String id, String userId);

    List<FutureLetter> findByUserIdAndStatusOrderByScheduledDateAsc(String userId, String status);

    List<FutureLetter> findByUserIdAndScheduledDateBeforeAndStatusOrderByScheduledDateAsc(
            String userId, LocalDate date, String status);
}
