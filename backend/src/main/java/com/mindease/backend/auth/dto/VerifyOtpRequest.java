package com.mindease.backend.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record VerifyOtpRequest(
        @NotBlank(message = "Email is required")
        @Email(message = "Enter a valid email address")
        String email,

        @NotBlank(message = "OTP is required")
        @Size(min = 6, max = 8, message = "Enter the complete verification code")
        @Pattern(regexp = "^[0-9]+$", message = "Code must contain only digits")
        String otp) {
}