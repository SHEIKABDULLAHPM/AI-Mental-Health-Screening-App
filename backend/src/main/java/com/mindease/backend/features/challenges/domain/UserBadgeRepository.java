package com.mindease.backend.features.challenges.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface UserBadgeRepository extends MongoRepository<UserBadge, String> {

    List<UserBadge> findByUserIdOrderByEarnedAtDesc(String userId);

    Optional<UserBadge> findByUserIdAndCode(String userId, String code);

    boolean existsByUserIdAndCode(String userId, String code);
}
