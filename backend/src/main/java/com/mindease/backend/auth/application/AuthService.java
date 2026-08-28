package com.mindease.backend.auth.application;

import java.time.Instant;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.mindease.backend.auth.domain.RefreshToken;
import com.mindease.backend.auth.domain.RefreshTokenRepository;
import com.mindease.backend.auth.dto.AuthResponse;
import com.mindease.backend.auth.dto.LoginRequest;
import com.mindease.backend.auth.dto.LogoutRequest;
import com.mindease.backend.auth.dto.RefreshRequest;
import com.mindease.backend.auth.dto.RegisterRequest;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.common.security.Tokens;
import com.mindease.backend.config.AppProperties;
import com.mindease.backend.security.JwtService;
import com.mindease.backend.user.domain.AccountStatus;
import com.mindease.backend.user.domain.User;
import com.mindease.backend.user.domain.UserRepository;
import com.mindease.backend.user.dto.UserProfileDto;

/**
 * Registration, login, refresh and logout.
 *
 * <p>Never accepts a userId from the client - identity is always derived from
 * the validated JWT or from the stored account.</p>
 */
@Service
public class AuthService {

    private static final java.util.regex.Pattern PASSWORD_POLICY =
            java.util.regex.Pattern.compile("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$");

    private final UserRepository users;
    private final RefreshTokenRepository refreshTokens;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwt;
    private final AppProperties props;
    private final AuditLog audit;

    public AuthService(UserRepository users,
                       RefreshTokenRepository refreshTokens,
                       PasswordEncoder passwordEncoder,
                       JwtService jwt,
                       AppProperties props,
                       AuditLog audit) {
        this.users = users;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.jwt = jwt;
        this.props = props;
        this.audit = audit;
    }

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        String email = request.email().trim().toLowerCase();
        if (request.password() == null || request.confirmPassword() == null
                || !request.password().equals(request.confirmPassword())) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "Passwords do not match");
        }
        if (!PASSWORD_POLICY.matcher(request.password()).matches()) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "Password must be at least 8 characters with a capital letter, "
                            + "a lowercase letter and a number");
        }
        if (users.existsByEmail(email)) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "An account already exists for this email. Please sign in.");
        }

        User user = new User();
        user.setEmail(email);
        user.setFullName(request.fullName().trim());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setCreatedAt(Instant.now());
        user.setUpdatedAt(Instant.now());
        user = users.save(user);

        audit.event(user.getId(), "register", "account created");
        return issueTokens(user);
    }

    public AuthResponse login(LoginRequest request) {
        String email = request.email().trim().toLowerCase();
        User user = users.findByEmail(email).orElseThrow(() -> unauthorized());
        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            audit.event(user.getId(), "login_failed", "invalid credentials");
            throw unauthorized();
        }
        if (user.getAccountStatus() != AccountStatus.ACTIVE) {
            throw new ApiException(ErrorCode.FORBIDDEN, "This account is not active.");
        }
        user.setLastLoginAt(Instant.now());
        user.setUpdatedAt(Instant.now());
        users.save(user);
        audit.event(user.getId(), "login", "authenticated");
        return issueTokens(user);
    }

    @Transactional
    public AuthResponse refresh(RefreshRequest request) {
        String hash = Tokens.sha256(request.refreshToken());
        RefreshToken record = refreshTokens.findByTokenHash(hash)
                .orElseThrow(this::unauthorized);
        if (record.getExpiresAt().isBefore(Instant.now())) {
            refreshTokens.delete(record);
            throw unauthorized();
        }
        User user = users.findById(record.getUserId()).orElseThrow(this::unauthorized);
        if (user.getAccountStatus() != AccountStatus.ACTIVE) {
            throw new ApiException(ErrorCode.FORBIDDEN, "Account is not active.");
        }
        // Rotate: the presented refresh token is single-use.
        refreshTokens.delete(record);
        audit.event(user.getId(), "token.refresh", "access refreshed");
        return issueTokens(user);
    }

    @Transactional
    public void logout(LogoutRequest request) {
        String hash = Tokens.sha256(request.refreshToken());
        refreshTokens.findByTokenHash(hash).ifPresent(record -> {
            audit.event(record.getUserId(), "logout", "refresh token revoked");
            refreshTokens.delete(record);
        });
    }

    private AuthResponse issueTokens(User user) {
        Instant now = Instant.now();
        String access = jwt.createAccessToken(user.getId(), now);
        String refresh = jwt.createRefreshToken(user.getId(), now);
        RefreshToken record = new RefreshToken(
                user.getId(),
                Tokens.sha256(refresh),
                now.plusSeconds(jwt.getRefreshExpirationSeconds()));
        refreshTokens.save(record);
        return new AuthResponse(access, refresh, jwt.getRefreshExpirationSeconds(),
                UserProfileDto.from(user));
    }

    private ApiException unauthorized() {
        return new ApiException(ErrorCode.UNAUTHORIZED, "Invalid email or password.");
    }

    public long refreshExpirationSeconds() {
        return jwt.getRefreshExpirationSeconds();
    }
}