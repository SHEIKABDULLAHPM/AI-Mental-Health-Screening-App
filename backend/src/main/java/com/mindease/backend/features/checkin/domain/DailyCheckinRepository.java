package com.mindease.backend.features.checkin.domain;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface DailyCheckinRepository extends MongoRepository<DailyCheckin, String> {

    Optional<DailyCheckin> findByUserIdAndDate(String userId, LocalDate date);

    List<DailyCheckin> findByUserIdOrderByDateDesc(String userId, Pageable pageable);

    long countByUserId(String userId);
}
