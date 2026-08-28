package com.mindease.backend.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import com.fasterxml.jackson.annotation.JsonProperty;

public record ResetPasswordRequest(
        @NotBlank(message = "Email is required")
        @Email(message = "Enter a valid email address")
        String email,

        @NotBlank(message = "Reset token is required")
        String resetToken,

        @NotBlank(message = "Password is required")
        @Size(min = 8, max = 64, message = "Password must be 8+ characters")
        String newPassword,

        @JsonProperty("confirmPassword")
        String confirmPassword) {
}