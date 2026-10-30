package com.mindease.backend.media;

import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Authenticated encryption for journal media at rest.
 *
 * <p>Journal text is sealed by {@code JournalCipher}, but image, audio and video
 * objects were previously written to object storage as plain bytes. This seals
 * them too, with AES-256-GCM, so a database or bucket dump does not expose a
 * user's photos, voice notes or recordings.</p>
 *
 * <p>Media is far larger than a text field, so the object is sealed in fixed
 * 1 MiB chunks instead of one buffer: both directions stream with memory
 * bounded to a single chunk, and a truncated or tampered chunk fails its tag
 * rather than decrypting to garbage. The layout is</p>
 *
 * <pre>
 *   "MBE2"            4 bytes  format marker
 *   nonce prefix      4 bytes  random per object
 *   repeated:
 *     length          4 bytes  big-endian size of the sealed chunk
 *     sealed chunk    length   ciphertext followed by the 16-byte GCM tag
 * </pre>
 *
 * <p>Each chunk gets its own IV built from the object's nonce prefix plus a
 * big-endian chunk counter, and the header is authenticated as additional data,
 * so chunks cannot be reordered or spliced between objects.</p>
 *
 * <p>When no key is configured the cipher is disabled and media is stored
 * exactly as before; production should always configure one.</p>
 */
@Component
public class MediaCipher {

    static final byte[] MAGIC = {'M', 'B', 'E', '2'};
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int NONCE_PREFIX_BYTES = 4;
    private static final int HEADER_BYTES = MAGIC.length + NONCE_PREFIX_BYTES;
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final int TAG_BYTES = 16;
    /** Plaintext sealed per chunk; bounds memory for both directions. */
    static final int CHUNK_BYTES = 1 << 20;

    private final SecureRandom random = new SecureRandom();
    private final SecretKeySpec key;
    private final boolean enabled;

    public MediaCipher(@Value("${mindease.media.encryption-key:}") String secret) {
        this.enabled = secret != null && !secret.isBlank();
        this.key = enabled ? new SecretKeySpec(sha256(secret), "AES") : null;
    }

    public boolean isEnabled() {
        return enabled;
    }

    /** True when these leading bytes carry the sealed-media marker. */
    public static boolean looksEncrypted(byte[] firstBytes) {
        if (firstBytes == null || firstBytes.length < MAGIC.length) {
            return false;
        }
        for (int i = 0; i < MAGIC.length; i++) {
            if (firstBytes[i] != MAGIC[i]) {
                return false;
            }
        }
        return true;
    }

    /** Exact size of the sealed form of {@code plaintextLength} bytes. */
    public static long sealedLength(long plaintextLength) {
        if (plaintextLength <= 0) {
            return HEADER_BYTES;
        }
        long chunks = (plaintextLength + CHUNK_BYTES - 1) / CHUNK_BYTES;
        return HEADER_BYTES + plaintextLength + chunks * (4L + TAG_BYTES);
    }

    /**
     * Wraps {@code plaintext} in a lazily sealing stream. The caller must know
     * the size up front ({@link #sealedLength(long)}) because object stores
     * need a content length before the body is read.
     */
    public InputStream encrypting(InputStream plaintext) throws IOException {
        requireEnabled();
        byte[] header = new byte[HEADER_BYTES];
        System.arraycopy(MAGIC, 0, header, 0, MAGIC.length);
        byte[] noncePrefix = new byte[NONCE_PREFIX_BYTES];
        random.nextBytes(noncePrefix);
        System.arraycopy(noncePrefix, 0, header, MAGIC.length, NONCE_PREFIX_BYTES);
        return new SealingStream(plaintext, header);
    }

    /**
     * Wraps a sealed object in a lazily opening stream. Throws when the object
     * is not sealed media, so callers can detect legacy plaintext objects.
     */
    public InputStream decrypting(InputStream sealed) throws IOException {
        requireEnabled();
        byte[] header = new byte[HEADER_BYTES];
        readFully(sealed, header);
        if (!looksEncrypted(header)) {
            throw new IOException("Object is not sealed media.");
        }
        return new OpeningStream(sealed, header);
    }

    private void requireEnabled() {
        if (!enabled) {
            throw new IllegalStateException("Media encryption is not configured.");
        }
    }

    private static byte[] ivFor(byte[] header, long counter) {
        byte[] iv = new byte[IV_BYTES];
        System.arraycopy(header, MAGIC.length, iv, 0, NONCE_PREFIX_BYTES);
        for (int i = 0; i < 8; i++) {
            iv[NONCE_PREFIX_BYTES + i] = (byte) (counter >>> (8 * (7 - i)));
        }
        return iv;
    }

    private byte[] seal(byte[] plain, int length, byte[] header, long counter)
            throws IOException {
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, key,
                    new GCMParameterSpec(TAG_BITS, ivFor(header, counter)));
            cipher.updateAAD(header);
            byte[] out = new byte[cipher.getOutputSize(length)];
            int written = cipher.doFinal(plain, 0, length, out, 0);
            return written == out.length ? out : Arrays.copyOf(out, written);
        } catch (Exception e) {
            throw new IOException("Media encryption failed.", e);
        }
    }

    private byte[] open(byte[] sealedChunk, byte[] header, long counter)
            throws IOException {
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key,
                    new GCMParameterSpec(TAG_BITS, ivFor(header, counter)));
            cipher.updateAAD(header);
            return cipher.doFinal(sealedChunk);
        } catch (Exception e) {
            throw new IOException(
                    "Media decryption failed; the key may have changed or the object "
                            + "is corrupt.", e);
        }
    }

    /** Streams plaintext in and framed ciphertext out, one chunk at a time. */
    private final class SealingStream extends InputStream {

        private final InputStream source;
        private final byte[] header;
        private long counter;
        private byte[] block;
        private int blockPos;

        SealingStream(InputStream source, byte[] header) {
            this.source = source;
            this.header = header;
            this.block = header;
        }

        @Override
        public int read() throws IOException {
            byte[] single = new byte[1];
            int read = read(single, 0, 1);
            return read < 0 ? -1 : single[0] & 0xff;
        }

        @Override
        public int read(byte[] target, int offset, int length) throws IOException {
            if (length == 0) {
                return 0;
            }
            if (blockPos >= block.length) {
                block = nextFrame();
                blockPos = 0;
                if (block == null) {
                    return -1;
                }
            }
            int copied = Math.min(length, block.length - blockPos);
            System.arraycopy(block, blockPos, target, offset, copied);
            blockPos += copied;
            return copied;
        }

        private byte[] nextFrame() throws IOException {
            byte[] plain = new byte[CHUNK_BYTES];
            int filled = 0;
            while (filled < CHUNK_BYTES) {
                int read = source.read(plain, filled, CHUNK_BYTES - filled);
                if (read < 0) {
                    break;
                }
                filled += read;
            }
            if (filled == 0) {
                return null;
            }
            byte[] sealedChunk = seal(plain, filled, header, counter++);
            byte[] frame = new byte[4 + sealedChunk.length];
            frame[0] = (byte) (sealedChunk.length >>> 24);
            frame[1] = (byte) (sealedChunk.length >>> 16);
            frame[2] = (byte) (sealedChunk.length >>> 8);
            frame[3] = (byte) sealedChunk.length;
            System.arraycopy(sealedChunk, 0, frame, 4, sealedChunk.length);
            return frame;
        }

        @Override
        public void close() throws IOException {
            source.close();
        }
    }

    /** Streams framed ciphertext in and plaintext out, one chunk at a time. */
    private final class OpeningStream extends InputStream {

        private final InputStream source;
        private final byte[] header;
        private long counter;
        private byte[] block = new byte[0];
        private int blockPos;
        private boolean finished;

        OpeningStream(InputStream source, byte[] header) {
            this.source = source;
            this.header = header;
        }

        @Override
        public int read() throws IOException {
            byte[] single = new byte[1];
            int read = read(single, 0, 1);
            return read < 0 ? -1 : single[0] & 0xff;
        }

        @Override
        public int read(byte[] target, int offset, int length) throws IOException {
            if (length == 0) {
                return 0;
            }
            if (blockPos >= block.length) {
                if (finished || !nextChunk()) {
                    finished = true;
                    return -1;
                }
            }
            int copied = Math.min(length, block.length - blockPos);
            System.arraycopy(block, blockPos, target, offset, copied);
            blockPos += copied;
            return copied;
        }

        private boolean nextChunk() throws IOException {
            int sealedLength = readIntOrEof(source);
            if (sealedLength < 0) {
                return false;
            }
            if (sealedLength <= TAG_BYTES) {
                throw new IOException("Sealed media chunk is truncated.");
            }
            byte[] sealedChunk = new byte[sealedLength];
            readFully(source, sealedChunk);
            block = open(sealedChunk, header, counter++);
            blockPos = 0;
            return true;
        }
    }

    private static void readFully(InputStream in, byte[] target) throws IOException {
        int offset = 0;
        while (offset < target.length) {
            int read = in.read(target, offset, target.length - offset);
            if (read < 0) {
                throw new EOFException("Unexpected end of media stream.");
            }
            offset += read;
        }
    }

    private static int readIntOrEof(InputStream in) throws IOException {
        int b0 = in.read();
        if (b0 < 0) {
            return -1;
        }
        byte[] rest = new byte[3];
        readFully(in, rest);
        return (b0 << 24) | ((rest[0] & 0xff) << 16) | ((rest[1] & 0xff) << 8)
                | (rest[2] & 0xff);
    }

    private static byte[] sha256(String secret) {
        try {
            return MessageDigest.getInstance("SHA-256")
                    .digest(secret.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 unavailable.", e);
        }
    }
}
