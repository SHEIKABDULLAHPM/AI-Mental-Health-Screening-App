package com.mindease.backend.features.journal.application;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Field-level authenticated encryption for journal text at rest.
 *
 * <p>MongoDB is not encrypted at the filesystem level in this deployment, so
 * the sensitive fields (title and body) would otherwise be readable by anyone
 * with database access. Values are sealed with AES-256-GCM and a random
 * 96-bit IV per write; the versioned prefix keeps legacy plaintext readable
 * and lets a future key rotation identify old ciphertext.</p>
 *
 * <p>The key is derived with SHA-256 from the configured secret, so operators
 * can supply any high-entropy string. When no key is configured encryption is
 * disabled and the value is stored unchanged - production startup rejects
 * that configuration (see {@code JournalEncryptionStartupValidator}).</p>
 */
@Component
public class JournalCipher {

    static final String PREFIX = "enc:v1:";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;

    private final SecureRandom random = new SecureRandom();
    private final SecretKeySpec key;
    private final boolean enabled;

    public JournalCipher(@Value("${mindease.journal.encryption-key:}") String secret) {
        this.enabled = secret != null && !secret.isBlank();
        this.key = enabled ? new SecretKeySpec(sha256(secret), "AES") : null;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public boolean isEncrypted(String value) {
        return value != null && value.startsWith(PREFIX);
    }

    /** Encrypts a value, leaving null/empty and already-encrypted values intact. */
    public String encrypt(String plaintext) {
        if (!enabled || plaintext == null || plaintext.isEmpty() || isEncrypted(plaintext)) {
            return plaintext;
        }
        try {
            byte[] iv = new byte[IV_BYTES];
            random.nextBytes(iv);
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            byte[] sealed = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            Base64.Encoder encoder = Base64.getUrlEncoder().withoutPadding();
            return PREFIX + encoder.encodeToString(iv) + ":" + encoder.encodeToString(sealed);
        } catch (Exception e) {
            throw new IllegalStateException("Journal encryption failed.", e);
        }
    }

    /**
     * Decrypts a stored value. Legacy plaintext (no prefix) is returned
     * unchanged. Tampered ciphertext throws instead of silently returning
     * garbage, because a failed authentication tag means the data is not
     * trustworthy.
     */
    public String decrypt(String stored) {
        if (stored == null || !isEncrypted(stored)) {
            return stored;
        }
        if (!enabled) {
            throw new IllegalStateException(
                    "Journal data is encrypted but no encryption key is configured.");
        }
        try {
            String[] parts = stored.substring(PREFIX.length()).split(":", 2);
            if (parts.length != 2) {
                throw new IllegalArgumentException("Malformed ciphertext.");
            }
            Base64.Decoder decoder = Base64.getUrlDecoder();
            byte[] iv = decoder.decode(parts[0]);
            byte[] sealed = decoder.decode(parts[1]);
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            return new String(cipher.doFinal(sealed), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Journal decryption failed; the key may have changed or the data is corrupt.",
                    e);
        }
    }

    private static byte[] sha256(String secret) {
        try {
            return MessageDigest.getInstance("SHA-256")
                    .digest(secret.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 unavailable.", e);
        }
    }
}
