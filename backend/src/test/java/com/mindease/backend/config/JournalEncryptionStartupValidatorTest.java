package com.mindease.backend.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * Production must never boot with an unset, short, or sample journal key:
 * that would silently store new entries in plaintext or under a public key.
 */
class JournalEncryptionStartupValidatorTest {

    private static final String STRONG =
            "9f3b1c7d2e8a4f60b5c9d1e7a3f8c2b6d4e0a9f5c1b7d3e8a2f6c4b0d9e5a1f7";

    @Test
    void devProfileAllowsAnUnsetKeyAndWarns() {
        var validator = new JournalEncryptionStartupValidator("", "dev");

        assertThatCode(() -> validator.run(null)).doesNotThrowAnyException();
    }

    @Test
    void productionRejectsUnsetShortAndSampleKeys() {
        for (String key : new String[] {
                "", "too-short", "change-me-dev-journal-key-0123456789abcdef"}) {
            var validator = new JournalEncryptionStartupValidator(key, "prod");
            assertThatThrownBy(() -> validator.run(null))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("JOURNAL_ENCRYPTION_KEY");
        }
    }

    @Test
    void productionAcceptsAStrongUniqueKey() {
        var validator = new JournalEncryptionStartupValidator(STRONG, "prod");

        assertThatCode(() -> validator.run(null)).doesNotThrowAnyException();
    }
}
