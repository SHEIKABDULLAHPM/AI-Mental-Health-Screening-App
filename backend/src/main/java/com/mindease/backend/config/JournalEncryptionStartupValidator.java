package com.mindease.backend.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * Refuses to start a production deployment without a journal encryption key.
 *
 * <p>Journal bodies are sealed at rest by {@code JournalCipher}. Booting
 * without a key would silently store new entries in plaintext, so the failure
 * is made explicit here rather than discovered during an incident. The dev
 * profile keeps working with the shared development key from {@code .env}.</p>
 */
@Component
public class JournalEncryptionStartupValidator implements ApplicationRunner {

    /** Any sample/dev key starts with this and must never reach production. */
    static final String PLACEHOLDER_PREFIX = "change-me";

    private static final Logger log =
            LoggerFactory.getLogger(JournalEncryptionStartupValidator.class);

    private final String key;
    private final String[] activeProfiles;

    public JournalEncryptionStartupValidator(
            @Value("${mindease.journal.encryption-key:}") String key,
            @Value("${spring.profiles.active:}") String activeProfiles) {
        this.key = key;
        this.activeProfiles = activeProfiles == null ? new String[0]
                : activeProfiles.split(",");
    }

    @Override
    public void run(ApplicationArguments args) {
        if (isDevOrTest()) {
            if (key == null || key.isBlank()) {
                log.warn("journal_encryption_disabled (dev/test profile): "
                        + "set JOURNAL_ENCRYPTION_KEY to exercise at-rest encryption");
                return;
            }
            log.debug("journal_encryption_enabled (dev/test profile)");
            return;
        }
        if (key == null || key.isBlank() || key.length() < 32
                || key.startsWith(PLACEHOLDER_PREFIX)
                || key.toLowerCase(java.util.Locale.ROOT).contains("dev-journal-key")) {
            throw new IllegalStateException(
                    "JOURNAL_ENCRYPTION_KEY must be a strong, unique secret of at least 32 "
                            + "characters. Unset, short, sample and dev-placeholder values "
                            + "are rejected outside the dev/test profiles.");
        }
        log.info("journal_encryption_enabled (production profile)");
    }

    private boolean isDevOrTest() {
        for (String profile : activeProfiles) {
            String p = profile == null ? "" : profile.trim();
            if (p.equals("dev") || p.equals("test")) {
                return true;
            }
        }
        return false;
    }
}
