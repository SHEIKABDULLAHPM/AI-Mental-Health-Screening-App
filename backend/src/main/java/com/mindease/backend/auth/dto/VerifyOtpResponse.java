package com.mindease.backend.auth.dto;

/** Successful OTP verification — an opaque, single-use reset session token. */
public record VerifyOtpResponse(String resetToken, long expiresIn) {
}