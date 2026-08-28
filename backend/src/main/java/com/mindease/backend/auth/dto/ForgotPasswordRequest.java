package com.mindease.backend.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record ForgotPasswordRequest(
        @NotBlank(message = "Email is required")
        @Email(message = "Enter a valid email address")
        String email) {

    public String normalizedEmail() {
        return email == null ? null : email.trim().toLowerCase();
    }
}