package com.mindease.backend.auth.application;

import java.time.Instant;
import java.util.regex.Pattern;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.mindease.backend.auth.domain.PasswordReset;
import com.mindease.backend.auth.domain.PasswordResetRepository;
import com.mindease.backend.auth.domain.RefreshTokenRepository;
import com.mindease.backend.auth.dto.ForgotPasswordRequest;
import com.mindease.backend.auth.dto.ResetPasswordRequest;
import com.mindease.backend.auth.dto.VerifyOtpRequest;
import com.mindease.backend.auth.dto.VerifyOtpResponse;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.common.security.Tokens;
import com.mindease.backend.config.AppProperties;
import com.mindease.backend.user.domain.User;
import com.mindease.backend.user.domain.UserRepository;

/**
 * Forgot-password flow: request OTP -&gt; verify OTP -&gt; reset password.
 *
 * <p>OTP values are hashed at rest and never written to logs or API bodies.
 * Unknown emails receive the same success response to avoid account
 * enumeration. Attempt limits protect against brute force.</p>
 */
@Service
public class PasswordResetService {

    private static final Pattern PASSWORD_POLICY =
            Pattern.compile("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).{8,}$");

    private final PasswordResetRepository resets;
    private final UserRepository users;
    private final RefreshTokenRepository refreshTokens;
    private final PasswordEncoder passwordEncoder;
    private final OtpGenerator otpGenerator;
    private final MailService mail;
    private final AppProperties props;
    private final AuditLog audit;

    public PasswordResetService(PasswordResetRepository resets,
                                UserRepository users,
                                RefreshTokenRepository refreshTokens,
                                PasswordEncoder passwordEncoder,
                                OtpGenerator otpGenerator,
                                MailService mail,
                                AppProperties props,
                                AuditLog audit) {
        this.resets = resets;
        this.users = users;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.otpGenerator = otpGenerator;
        this.mail = mail;
        this.props = props;
        this.audit = audit;
    }

    /**
     * Generates and stores a fresh OTP. Always returns success so unregistered
     * emails cannot be distinguished from registered ones.
     */
    public void requestReset(ForgotPasswordRequest request) {
        String email = request.normalizedEmail();
        var user = users.findByEmail(email);
        if (user.isEmpty()) {
            audit.event(null, "password.reset_requested", "unknown email");
            return;
        }

        resets.deleteByEmail(email);
        PasswordReset record = new PasswordReset();
        record.setUserId(user.get().getId());
        record.setEmail(email);
        String otp = otpGenerator.generate(props.getOtp().getLength());
        record.setOtpHash(Tokens.sha256(otp));
        record.setState(PasswordReset.State.OTP_PENDING);
        record.setExpiresAt(Instant.now().plus(props.getOtp().getExpiration()));
        record.setCreatedAt(Instant.now());
        resets.save(record);

        audit.event(user.get().getId(), "password.reset_requested", "otp issued");
        mail.sendPasswordResetOtp(email, otp);
    }

    /**
     * Validates the OTP against the stored hash and, on success, issues a
     * single-use reset token.
     */
    public VerifyOtpResponse verifyOtp(VerifyOtpRequest request) {
        String email = request.email().trim().toLowerCase();
        PasswordReset record = resets.findTopByEmailOrderByCreatedAtDesc(email)
                .orElseThrow(() -> invalidCode());

        if (record.getState() != PasswordReset.State.OTP_PENDING
                || record.getExpiresAt().isBefore(Instant.now())) {
            throw invalidCode();
        }
        int maxAttempts = props.getOtp().getMaxAttempts();
        if (record.getAttempts() >= maxAttempts) {
            throw invalidCode();
        }

        if (!Tokens.constantTimeEquals(record.getOtpHash(), Tokens.sha256(request.otp()))) {
            record.setAttempts(record.getAttempts() + 1);
            if (record.getAttempts() >= maxAttempts) {
                record.setState(PasswordReset.State.EXPIRED);
            }
            resets.save(record);
            audit.event(record.getUserId(), "otp.verify_failed", "attempt count");
            throw invalidCode();
        }

        // Issue a fresh expiry window for the reset step. Without this the
        // user must complete the whole flow (verify OTP + choose a new
        // password) within the original OTP deadline, which is too tight and
        // competes with the Mongo TTL index that physically deletes the record.
        Instant resetDeadline = Instant.now().plus(props.getOtp().getExpiration());
        record.setExpiresAt(resetDeadline);

        String resetToken = Tokens.randomToken(32);
        record.setResetTokenHash(Tokens.sha256(resetToken));
        record.setState(PasswordReset.State.VERIFIED);
        resets.save(record);
        audit.event(record.getUserId(), "otp.verified", "reset token issued");
        return new VerifyOtpResponse(resetToken, resetDeadline.getEpochSecond() - Instant.now().getEpochSecond());
    }

    /** Applies the new password and invalidates the whole reset session. */
    public void resetPassword(ResetPasswordRequest request) {
        String email = request.email().trim().toLowerCase();
        PasswordReset record = resets.findTopByEmailOrderByCreatedAtDesc(email)
                .orElseThrow(() -> invalidReset());

        if (record.getState() != PasswordReset.State.VERIFIED
                || record.getResetTokenHash() == null
                || !Tokens.constantTimeEquals(record.getResetTokenHash(),
                        Tokens.sha256(request.resetToken()))
                || record.getExpiresAt().isBefore(Instant.now())) {
            throw invalidReset();
        }
        if (request.newPassword() == null || request.confirmPassword() == null
                || !request.newPassword().equals(request.confirmPassword())) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED, "Passwords do not match");
        }
        if (!PASSWORD_POLICY.matcher(request.newPassword()).matches()) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "Password must be at least 8 characters with a capital letter, "
                            + "a lowercase letter and a number");
        }

        User user = users.findByEmail(email).orElseThrow(() -> invalidReset());
        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        user.setUpdatedAt(Instant.now());
        users.save(user);

        // Invalidate: reset session and all existing sessions for this user.
        record.setState(PasswordReset.State.USED);
        record.setOtpHash(null);
        record.setResetTokenHash(null);
        resets.save(record);
        refreshTokens.deleteByUserId(user.getId());

        audit.event(user.getId(), "password.reset", "password updated");
    }

    private ApiException invalidCode() {
        return new ApiException(ErrorCode.UNAUTHORIZED, "Invalid or expired verification code.");
    }

    private ApiException invalidReset() {
        return new ApiException(ErrorCode.UNAUTHORIZED,
                "This reset link is invalid or has expired. Please request a new code.");
    }
}