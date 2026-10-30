package com.mindease.backend.media;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Random;

import org.junit.jupiter.api.Test;

/**
 * Journal media used to be written to object storage as plain bytes. These
 * tests pin the sealing that closes that gap: a round trip of arbitrary size,
 * a size that spans several chunks, tamper detection, and the legacy
 * plaintext path so switching encryption on cannot strand earlier media.
 */
class MediaCipherTest {

    private static final String KEY = "test-media-encryption-key-0123456789";

    private final MediaCipher cipher = new MediaCipher(KEY);

    private static byte[] randomBytes(int size) {
        byte[] data = new byte[size];
        new Random(size).nextBytes(data);
        return data;
    }

    private byte[] seal(byte[] plaintext) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream in = cipher.encrypting(new ByteArrayInputStream(plaintext))) {
            in.transferTo(out);
        }
        return out.toByteArray();
    }

    private byte[] open(byte[] sealed) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream in = cipher.decrypting(new ByteArrayInputStream(sealed))) {
            in.transferTo(out);
        }
        return out.toByteArray();
    }

    @Test
    void roundTripsContentSmallerThanOneChunk() throws Exception {
        byte[] plaintext = randomBytes(4_096);

        byte[] sealed = seal(plaintext);

        assertThat(sealed).isNotEqualTo(plaintext);
        assertThat(open(sealed)).isEqualTo(plaintext);
        assertThat(MediaCipher.looksEncrypted(sealed)).isTrue();
    }

    @Test
    void roundTripsContentSpanningSeveralChunks() throws Exception {
        byte[] plaintext = randomBytes(MediaCipher.CHUNK_BYTES * 2 + 12_345);

        byte[] sealed = seal(plaintext);

        assertThat(sealed.length).isEqualTo(MediaCipher.sealedLength(plaintext.length));
        assertThat(open(sealed)).isEqualTo(plaintext);
    }

    @Test
    void sealedLengthMatchesWhatIsWrittenForNonChunkAlignedSizes() throws Exception {
        for (int size : new int[] {1, MediaCipher.CHUNK_BYTES, MediaCipher.CHUNK_BYTES + 1}) {
            byte[] plaintext = randomBytes(size);
            assertThat(seal(plaintext).length)
                    .as("sealed size for %s bytes", size)
                    .isEqualTo(MediaCipher.sealedLength(size));
        }
    }

    @Test
    void aTamperedChunkFailsInsteadOfReturningGarbage() throws Exception {
        byte[] sealed = seal(randomBytes(2_048));
        sealed[sealed.length - 1] ^= 0x01;

        assertThatThrownBy(() -> open(sealed))
                .isInstanceOf(IOException.class)
                .hasMessageContaining("decryption failed");
    }

    @Test
    void aTruncatedObjectFailsInsteadOfReturningPartialMedia() throws Exception {
        byte[] sealed = seal(randomBytes(2_048));
        byte[] truncated = java.util.Arrays.copyOf(sealed, sealed.length - 8);

        assertThatThrownBy(() -> open(truncated)).isInstanceOf(IOException.class);
    }

    @Test
    void plaintextIsRecognisedSoEarlierMediaStaysReadable() {
        assertThat(MediaCipher.looksEncrypted("plain image bytes".getBytes())).isFalse();
        assertThat(MediaCipher.looksEncrypted(new byte[2])).isFalse();
        assertThat(MediaCipher.looksEncrypted(null)).isFalse();
    }

    @Test
    void withoutAKeyTheCipherIsOffAndRefusesToPretendItSealedSomething() {
        MediaCipher off = new MediaCipher("");

        assertThat(off.isEnabled()).isFalse();
        assertThatThrownBy(() -> off.encrypting(new ByteArrayInputStream(new byte[1])))
                .isInstanceOf(IllegalStateException.class);
    }
}
