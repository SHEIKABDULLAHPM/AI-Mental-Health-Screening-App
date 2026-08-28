package com.mindease.backend.auth.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A password-reset session: OTP challenge + post-verification reset token.
 *
 * <p>Only hashes are persisted (OTP and reset token) — the plain values are
 * never readable from the database or logs.</p>
 */
@Document(collection = "password_reset")
public class PasswordReset {

    public enum State { OTP_PENDING, VERIFIED, USED, EXPIRED }

    @Id
    private String id;

    @Indexed
    private String userId;

    private String tenantId = "app";

    @Indexed
    private String email;

    /** SHA-256 hash of the 6-digit email OTP. */
    private String otpHash;

    /** SHA-256 hash of the reset token handed back after OTP verification. */
    private String resetTokenHash;

    private int attempts;

    private State state = State.OTP_PENDING;

    /** TTL index removes stale sessions. */
    @Indexed(expireAfterSeconds = 0)
    private Instant expiresAt;

    private Instant createdAt;

    public PasswordReset() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getOtpHash() {
        return otpHash;
    }

    public void setOtpHash(String otpHash) {
        this.otpHash = otpHash;
    }

    public String getResetTokenHash() {
        return resetTokenHash;
    }

    public void setResetTokenHash(String resetTokenHash) {
        this.resetTokenHash = resetTokenHash;
    }

    public int getAttempts() {
        return attempts;
    }

    public void setAttempts(int attempts) {
        this.attempts = attempts;
    }

    public State getState() {
        return state;
    }

    public void setState(State state) {
        this.state = state;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public void setExpiresAt(Instant expiresAt) {
        this.expiresAt = expiresAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }
}