package com.mindease.backend.auth.application;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

/**
 * SMTP-backed OTP delivery.
 *
 * <p>When a mail host is configured the OTP is emailed. When it is not (the
 * common development/test case) the send is skipped and the OTP is surfaced in
 * the server log instead so the flow remains fully testable. In production
 * {@code MAIL_HOST} is always set, so the OTP is never written to logs there.</p>
 */
@Service
public class SmtpMailService implements MailService {

    private static final Logger log = LoggerFactory.getLogger(SmtpMailService.class);

    private final JavaMailSender sender;
    private final String from;
    private final boolean enabled;

    public SmtpMailService(ObjectProvider<JavaMailSender> mailSenderProvider,
                           @Value("${spring.mail.from:}") String from,
                           @Value("${spring.mail.host:}") String mailHost) {
        this.sender = mailSenderProvider.getIfAvailable();
        this.from = from;
        // A JavaMailSender bean is created by Spring even when the host is
        // empty, so the presence of the bean alone is not enough. Only treat
        // mail as usable when a non-empty host is configured.
        this.enabled = sender != null && !mailHost.isBlank();
    }

    @Override
    public void sendPasswordResetOtp(String to, String otp) {
        if (!enabled) {
            // No SMTP host configured: surface the OTP via the server log so the
            // flow stays testable without a mail server. This branch never runs
            // in production because MAIL_HOST is always set there.
            log.info("SMTP not configured — dev OTP for {}: {}", to, otp);
            return;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(from);
            message.setTo(to);
            message.setSubject("Your Synora verification code");
            message.setText("Your password reset verification code is: " + otp
                    + "\n\nIt expires in 10 minutes. If you did not request this,"
                    + " you can safely ignore this email.");
            sender.send(message);
            log.debug("Password reset OTP sent to {}", to);
        } catch (RuntimeException ex) {
            log.warn("Failed to send password reset email to {}: {}", to, ex.getMessage());
        }
    }
}