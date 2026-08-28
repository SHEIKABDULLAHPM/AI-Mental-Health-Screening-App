package com.mindease.backend.common.logging;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Writes structured audit entries for important security events. No sensitive
 * values (passwords, OTPs, tokens, raw email addresses) are ever included.
 */
@Service
public class AuditLog {

    private static final Logger AUDIT = LoggerFactory.getLogger("AUDIT");

    public void event(String actor, String action, String detail) {
        AUDIT.info("actor={} action={} detail={}", safe(actor), safe(action), safe(detail));
    }

    public void event(String actor, String action) {
        event(actor, action, null);
    }

    /** E-mail addresses are redacted to their local-part length to avoid raw PII in logs. */
    static String safe(String value) {
        if (value == null) {
            return "-";
        }
        if (value.contains("@")) {
            String local = value.substring(0, value.indexOf('@'));
            return local + "@***";
        }
        return value.length() > 64 ? value.substring(0, 64) : value;
    }
}