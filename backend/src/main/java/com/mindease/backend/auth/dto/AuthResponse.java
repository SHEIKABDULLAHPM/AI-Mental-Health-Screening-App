package com.mindease.backend.auth.dto;

import com.mindease.backend.user.dto.UserProfileDto;

/** Token pair handed back after registration/login/refresh. */
public record AuthResponse(
        String accessToken,
        String refreshToken,
        long expiresIn,
        UserProfileDto user) {
}