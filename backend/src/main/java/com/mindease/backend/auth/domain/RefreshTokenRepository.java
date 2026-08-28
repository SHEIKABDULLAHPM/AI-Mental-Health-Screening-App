package com.mindease.backend.auth.domain;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface RefreshTokenRepository extends MongoRepository<RefreshToken, String> {

    Optional<RefreshToken> findByTokenHash(String tokenHash);

    long deleteByUserId(String userId);
}