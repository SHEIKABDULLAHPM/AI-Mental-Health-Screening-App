package com.mindease.backend.features.futureletters.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.futureletters.application.FutureLetterService;
import com.mindease.backend.features.futureletters.dto.CreateLetterRequest;
import com.mindease.backend.features.futureletters.dto.LetterResponse;
import com.mindease.backend.features.futureletters.dto.UpdateLetterRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/future-letters")
public class FutureLetterController {

    private final FutureLetterService service;

    public FutureLetterController(FutureLetterService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<LetterResponse>> create(
            @Valid @RequestBody CreateLetterRequest request) {
        String userId = AuthenticatedUser.currentId();
        LetterResponse response = service.createLetter(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<LetterResponse>>> listAll() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getUserLetters(userId)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<LetterResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getLetterById(userId, id)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<LetterResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateLetterRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.updateLetter(userId, id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        service.deleteLetter(userId, id);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    @GetMapping("/scheduled")
    public ResponseEntity<ApiResponse<List<LetterResponse>>> listScheduled() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getScheduledLetters(userId)));
    }

    @GetMapping("/delivered")
    public ResponseEntity<ApiResponse<List<LetterResponse>>> listDelivered() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getDeliveredLetters(userId)));
    }

    @PutMapping("/{id}/open")
    public ResponseEntity<ApiResponse<LetterResponse>> markAsOpened(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.markAsOpened(userId, id)));
    }
}
