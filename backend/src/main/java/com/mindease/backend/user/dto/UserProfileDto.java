package com.mindease.backend.user.dto;

import java.time.Instant;

import com.mindease.backend.user.domain.AccountStatus;
import com.mindease.backend.user.domain.ConsentStatus;
import com.mindease.backend.user.domain.OnboardingStatus;
import com.mindease.backend.user.domain.ScreeningStatus;
import com.mindease.backend.user.domain.User;

/**
 * Safe projection of the account exposed over the API. Never includes the
 * password hash.
 */
public record UserProfileDto(
        String id,
        String email,
        String fullName,
        AccountStatus accountStatus,
        OnboardingStatus onboardingStatus,
        ConsentStatus consentStatus,
        ScreeningStatus screeningStatus,
        Instant createdAt,
        Instant updatedAt,
        Instant lastLoginAt) {

    public static UserProfileDto from(User user) {
        return new UserProfileDto(
                user.getId(),
                user.getEmail(),
                user.getFullName(),
                user.getAccountStatus(),
                user.getOnboardingStatus(),
                user.getConsentStatus(),
                user.getScreeningStatus(),
                user.getCreatedAt(),
                user.getUpdatedAt(),
                user.getLastLoginAt());
    }
}