package com.mindease.backend.media;

import java.io.InputStream;
import java.time.Instant;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

@Service
public class MediaService {

    private static final Logger log = LoggerFactory.getLogger(MediaService.class);

    private static final long MAX_IMAGE_SIZE = 10 * 1024 * 1024;  // 10 MB
    private static final long MAX_AUDIO_SIZE = 50 * 1024 * 1024;  // 50 MB
    private static final long MAX_VIDEO_SIZE = 100 * 1024 * 1024; // 100 MB
    private static final int MAX_AUDIO_DURATION_SECONDS = 600;    // 10 min

    private static final Set<String> ALLOWED_IMAGE_TYPES = Set.of(
            "image/jpeg", "image/png", "image/webp", "image/heic");

    private static final Set<String> ALLOWED_AUDIO_TYPES = Set.of(
            "audio/mpeg", "audio/mp4", "audio/aac", "audio/ogg",
            "audio/wav", "audio/x-m4a");

    private static final Set<String> ALLOWED_VIDEO_TYPES = Set.of(
            "video/mp4", "video/quicktime", "video/x-msvideo",
            "video/webm", "video/3gpp");

    private final S3Client s3Client;
    private final S3Presigner presigner;
    private final MediaConfig config;

    public MediaService(S3Client s3Client, S3Presigner presigner, MediaConfig config) {
        this.s3Client = s3Client;
        this.presigner = presigner;
        this.config = config;
    }

    /**
     * Upload a file to MinIO under a user-scoped path.
     *
     * @return the object key (stored as reference, never exposed to client)
     */
    public MediaReference upload(String userId, MultipartFile file, MediaType mediaType) {
        validateFile(file, mediaType);

        String key = buildKey(userId, mediaType, file.getOriginalFilename());

        try (InputStream is = file.getInputStream()) {
            s3Client.putObject(
                    PutObjectRequest.builder()
                            .bucket(config.getBucket())
                            .key(key)
                            .contentType(file.getContentType())
                            .build(),
                    RequestBody.fromInputStream(is, file.getSize()));
        } catch (Exception e) {
            log.warn("media_upload_failed userId={} type={}", userId, mediaType);
            throw new ApiException(ErrorCode.INTERNAL_ERROR,
                    "Failed to upload media. Please try again.");
        }

        log.info("media_uploaded userId={} type={} size={}", userId, mediaType, file.getSize());

        return new MediaReference(
                key,
                mediaType.name(),
                file.getOriginalFilename(),
                file.getContentType(),
                file.getSize(),
                Instant.now());
    }

    /**
     * Generate a presigned URL for secure, time-limited access.
     */
    public String getPresignedUrl(String objectKey) {
        if (objectKey == null || objectKey.isBlank()) return null;
        try {
            return presigner.presignGetObject(
                    GetObjectPresignRequest.builder()
                            .signatureDuration(java.time.Duration.ofMinutes(15))
                            .getObjectRequest(GetObjectRequest.builder()
                                    .bucket(config.getBucket())
                                    .key(objectKey)
                                    .build())
                            .build())
                    .url()
                    .toString();
        } catch (Exception e) {
            log.warn("presign_failed key={}", objectKey);
            return null;
        }
    }

    /**
     * Delete a media object. Failures are logged but not propagated
     * (media cleanup should not block journal operations).
     */
    public void delete(String objectKey) {
        if (objectKey == null || objectKey.isBlank()) return;
        try {
            s3Client.deleteObject(DeleteObjectRequest.builder()
                    .bucket(config.getBucket())
                    .key(objectKey)
                    .build());
            log.info("media_deleted key={}", objectKey);
        } catch (Exception e) {
            log.warn("media_delete_failed key={}", objectKey);
        }
    }

    private void validateFile(MultipartFile file, MediaType mediaType) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "File is empty.");
        }

        String contentType = file.getContentType();
        long size = file.getSize();

        if (mediaType == MediaType.IMAGE) {
            if (!ALLOWED_IMAGE_TYPES.contains(contentType)) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Unsupported image type. Allowed: JPEG, PNG, WebP, HEIC.");
            }
            if (size > MAX_IMAGE_SIZE) {
                throw new ApiException(ErrorCode.PAYLOAD_TOO_LARGE,
                        "Image must be under 10 MB.");
            }
        } else if (mediaType == MediaType.AUDIO) {
            if (!ALLOWED_AUDIO_TYPES.contains(contentType)) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Unsupported audio type. Allowed: MP3, AAC, OGG, WAV, M4A.");
            }
            if (size > MAX_AUDIO_SIZE) {
                throw new ApiException(ErrorCode.PAYLOAD_TOO_LARGE,
                        "Audio must be under 50 MB.");
            }
        } else if (mediaType == MediaType.VIDEO) {
            if (!ALLOWED_VIDEO_TYPES.contains(contentType)) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Unsupported video type. Allowed: MP4, MOV, AVI, WebM, 3GP.");
            }
            if (size > MAX_VIDEO_SIZE) {
                throw new ApiException(ErrorCode.PAYLOAD_TOO_LARGE,
                        "Video must be under 100 MB.");
            }
        }
    }

    private String buildKey(String userId, MediaType mediaType, String originalFilename) {
        String ext = "";
        if (originalFilename != null && originalFilename.contains(".")) {
            ext = originalFilename.substring(originalFilename.lastIndexOf('.'));
        }
        String folder = switch (mediaType) {
            case IMAGE -> "images";
            case AUDIO -> "audio";
            case VIDEO -> "video";
        };
        return "journal/" + userId + "/" + folder + "/" + UUID.randomUUID() + ext;
    }

    public enum MediaType { IMAGE, AUDIO, VIDEO }

    public record MediaReference(
            String key,
            String mediaType,
            String originalFilename,
            String contentType,
            long size,
            Instant uploadedAt) {}
}
