package com.mindease.backend.media;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Signed, time-limited access tokens for the media download endpoint.
 *
 * <p>Sealed media cannot be handed out as a storage presigned URL, because the
 * bytes have to pass through the backend to be decrypted. The download endpoint
 * therefore carries its own authorization: an expiry and an HMAC over the object
 * key. The token grants access to exactly one object and expires, which keeps
 * the behaviour equivalent to the presigned URL it replaces.</p>
 */
@Component
public class MediaAccessToken {

    private static final String ALGORITHM = "HmacSHA256";
    private static final long TTL_SECONDS = 900L;

    private final SecretKeySpec key;
    private final boolean enabled;

    public MediaAccessToken(
            @Value("${mindease.media.access-secret:}") String accessSecret,
            @Value("${mindease.media.encryption-key:}") String encryptionKey) {
        String secret = accessSecret != null && !accessSecret.isBlank()
                ? accessSecret
                : encryptionKey;
        this.enabled = secret != null && !secret.isBlank();
        this.key = enabled ? new SecretKeySpec(sha256(secret), ALGORITHM) : null;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public long ttlSeconds() {
        return TTL_SECONDS;
    }

    /** Signature for {@code objectKey} that stops being valid at {@code expiry}. */
    public String sign(String objectKey, long expiry) {
        if (!enabled) {
            throw new IllegalStateException("Media access signing is not configured.");
        }
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(key);
            byte[] raw = mac.doFinal(
                    (objectKey + "|" + expiry).getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        } catch (Exception e) {
            throw new IllegalStateException("Media access signing failed.", e);
        }
    }

    /** Constant-time check that {@code signature} is this object's, and unexpired. */
    public boolean verify(String objectKey, long expiry, String signature) {
        if (!enabled || objectKey == null || objectKey.isBlank()
                || signature == null || signature.isBlank()) {
            return false;
        }
        if (expiry < System.currentTimeMillis() / 1000L) {
            return false;
        }
        byte[] expected = sign(objectKey, expiry).getBytes(StandardCharsets.UTF_8);
        byte[] supplied = signature.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, supplied);
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
