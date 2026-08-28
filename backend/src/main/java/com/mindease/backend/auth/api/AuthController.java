package com.mindease.backend.auth.api;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.auth.application.AuthService;
import com.mindease.backend.auth.application.PasswordResetService;
import com.mindease.backend.auth.dto.AuthResponse;
import com.mindease.backend.auth.dto.ForgotPasswordRequest;
import com.mindease.backend.auth.dto.LoginRequest;
import com.mindease.backend.auth.dto.LogoutRequest;
import com.mindease.backend.auth.dto.RefreshRequest;
import com.mindease.backend.auth.dto.RegisterRequest;
import com.mindease.backend.auth.dto.ResetPasswordRequest;
import com.mindease.backend.auth.dto.VerifyOtpRequest;
import com.mindease.backend.auth.dto.VerifyOtpResponse;
import com.mindease.backend.common.api.ApiResponse;

import jakarta.validation.Valid;

/**
 * Public authentication endpoints (rate limited per IP). Never validates an
 * account identity from a client-supplied id here.
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService auth;
    private final PasswordResetService reset;

    public AuthController(AuthService auth, PasswordResetService reset) {
        this.auth = auth;
        this.reset = reset;
    }

    @PostMapping("/register")
    public ResponseEntity<ApiResponse<AuthResponse>> register(
            @Valid @RequestBody RegisterRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(auth.register(request)));
    }

    @PostMapping("/login")
    public ResponseEntity<ApiResponse<AuthResponse>> login(
            @Valid @RequestBody LoginRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(auth.login(request)));
    }

    @PostMapping("/refresh")
    public ResponseEntity<ApiResponse<AuthResponse>> refresh(
            @Valid @RequestBody RefreshRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(auth.refresh(request)));
    }

    @PostMapping("/logout")
    public ResponseEntity<ApiResponse<Void>> logout(@Valid @RequestBody LogoutRequest request) {
        auth.logout(request);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    @PostMapping("/forgot-password")
    public ResponseEntity<ApiResponse<Void>> forgotPassword(
            @Valid @RequestBody ForgotPasswordRequest request) {
        reset.requestReset(request);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    @PostMapping("/verify-otp")
    public ResponseEntity<ApiResponse<VerifyOtpResponse>> verifyOtp(
            @Valid @RequestBody VerifyOtpRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(reset.verifyOtp(request)));
    }

    @PostMapping("/reset-password")
    public ResponseEntity<ApiResponse<Void>> resetPassword(
            @Valid @RequestBody ResetPasswordRequest request) {
        reset.resetPassword(request);
        return ResponseEntity.ok(ApiResponse.ok());
    }
}