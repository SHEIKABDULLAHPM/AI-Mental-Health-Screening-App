package com.mindease.backend.auth.domain;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface PasswordResetRepository extends MongoRepository<PasswordReset, String> {

    Optional<PasswordReset> findTopByEmailOrderByCreatedAtDesc(String email);

    long deleteByEmail(String email);
}