package com.mindease.backend.features.journal.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * Journal text must be sealed with authenticated encryption. These tests pin
 * the format, the round trip, legacy plaintext compatibility and tamper
 * detection.
 */
class JournalCipherTest {

    private static final String KEY = "unit-test-journal-key-0123456789abcdef";

    @Test
    void roundTripsUnicodeText() {
        JournalCipher cipher = new JournalCipher(KEY);
        String plaintext = "Today I felt calm — 日本語 and emoji 🙂";

        String sealed = cipher.encrypt(plaintext);

        assertThat(sealed).startsWith(JournalCipher.PREFIX);
        assertThat(sealed).doesNotContain(plaintext);
        assertThat(cipher.decrypt(sealed)).isEqualTo(plaintext);
    }

    @Test
    void usesAFreshIvForEachWrite() {
        JournalCipher cipher = new JournalCipher(KEY);

        String first = cipher.encrypt("same text");
        String second = cipher.encrypt("same text");

        assertThat(first).isNotEqualTo(second);
        assertThat(cipher.decrypt(first)).isEqualTo("same text");
        assertThat(cipher.decrypt(second)).isEqualTo("same text");
    }

    @Test
    void sameKeyMaterialDecryptsAcrossInstances() {
        String sealed = new JournalCipher(KEY).encrypt("persisted body");

        assertThat(new JournalCipher(KEY).decrypt(sealed)).isEqualTo("persisted body");
        assertThatThrownBy(() -> new JournalCipher(KEY + "-different").decrypt(sealed))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void legacyPlaintextIsReturnedUnchanged() {
        JournalCipher cipher = new JournalCipher(KEY);

        assertThat(cipher.decrypt("a legacy plaintext entry")).isEqualTo("a legacy plaintext entry");
        assertThat(cipher.isEncrypted("a legacy plaintext entry")).isFalse();
    }

    @Test
    void nullAndEmptyValuesAreSafe() {
        JournalCipher cipher = new JournalCipher(KEY);

        assertThat(cipher.encrypt(null)).isNull();
        assertThat(cipher.decrypt(null)).isNull();
        assertThat(cipher.encrypt("")).isEmpty();
        assertThat(cipher.decrypt("")).isEmpty();
    }

    @Test
    void tamperedCiphertextFailsAuthentication() {
        JournalCipher cipher = new JournalCipher(KEY);
        String sealed = cipher.encrypt("do not modify me");
        String tampered = sealed.substring(0, sealed.length() - 2)
                + (sealed.endsWith("A") ? "BB" : "AA");

        assertThatThrownBy(() -> cipher.decrypt(tampered))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("decryption failed");
    }

    @Test
    void disabledCipherLeavesValuesUnchanged() {
        JournalCipher cipher = new JournalCipher("");

        assertThat(cipher.isEnabled()).isFalse();
        assertThat(cipher.encrypt("plain")).isEqualTo("plain");
        assertThat(cipher.decrypt("plain")).isEqualTo("plain");
    }
}
