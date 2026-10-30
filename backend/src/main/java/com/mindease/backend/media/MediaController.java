package com.mindease.backend.media;

import java.io.InputStream;
import java.util.Map;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;

@RestController
@RequestMapping("/api/v1/media")
public class MediaController {

    private final MediaService mediaService;
    private final MediaAccessToken accessToken;

    public MediaController(MediaService mediaService, MediaAccessToken accessToken) {
        this.mediaService = mediaService;
        this.accessToken = accessToken;
    }

    @PostMapping("/upload")
    public ResponseEntity<ApiResponse<Map<String, Object>>> upload(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "type", defaultValue = "IMAGE") String type) {
        String userId = AuthenticatedUser.currentId();
        MediaService.MediaType mediaType = switch (type.toUpperCase()) {
            case "AUDIO" -> MediaService.MediaType.AUDIO;
            case "VIDEO" -> MediaService.MediaType.VIDEO;
            default -> MediaService.MediaType.IMAGE;
        };

        MediaService.MediaReference ref = mediaService.upload(userId, file, mediaType);

        return ResponseEntity.ok(ApiResponse.ok(Map.of(
                "key", ref.key(),
                "mediaType", ref.mediaType(),
                "contentType", ref.contentType(),
                "size", ref.size())));
    }

    /**
     * Streams one object to its owner-authorized holder.
     *
     * <p>Sealed media cannot be served by the object store directly, so the
     * bytes are decrypted here. Authorization is the short-lived signature the
     * backend put in the URL (see {@link MediaAccessToken}); the endpoint is
     * deliberately outside JWT auth because a browser or media player fetches
     * it without headers — exactly like the presigned URL it replaces.</p>
     */
    @GetMapping("/object")
    public ResponseEntity<StreamingResponseBody> download(
            @RequestParam("key") String key,
            @RequestParam("exp") long expiry,
            @RequestParam("sig") String signature) {
        if (!accessToken.verify(key, expiry, signature)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        MediaService.StoredMedia media;
        try {
            media = mediaService.open(key);
        } catch (RuntimeException e) {
            return ResponseEntity.notFound().build();
        }

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(media.contentType() == null
                ? MediaType.APPLICATION_OCTET_STREAM
                : MediaType.parseMediaType(media.contentType()));
        headers.setCacheControl("private, max-age=0, no-store");
        if (media.contentLength() >= 0) {
            headers.setContentLength(media.contentLength());
        }

        StreamingResponseBody body = output -> {
            try (InputStream in = media.stream()) {
                in.transferTo(output);
            }
        };
        return new ResponseEntity<>(body, headers, HttpStatus.OK);
    }

    @DeleteMapping
    public ResponseEntity<ApiResponse<Void>> delete(@RequestParam("key") String key) {
        String userId = AuthenticatedUser.currentId();
        // Enforce user-scoped path: key must start with journal/{userId}/
        if (key == null || !key.startsWith("journal/" + userId + "/")) {
            return ResponseEntity.ok(ApiResponse.ok());
        }
        mediaService.delete(key);
        return ResponseEntity.ok(ApiResponse.ok());
    }
}
