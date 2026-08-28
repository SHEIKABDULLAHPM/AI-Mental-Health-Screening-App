package com.mindease.backend.auth.application;

/**
 * Outbound channel used to deliver password-reset OTPs. The default SMTP
 * implementation only sends when a mail server is configured; the OTP value is
 * never logged by the backend.
 */
public interface MailService {

    void sendPasswordResetOtp(String to, String otp);
}