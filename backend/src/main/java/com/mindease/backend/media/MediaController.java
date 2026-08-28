package com.mindease.backend.media;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.security.AuthenticatedUser;

@RestController
@RequestMapping("/api/v1/media")
public class MediaController {

    private final MediaService mediaService;

    public MediaController(MediaService mediaService) {
        this.mediaService = mediaService;
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
