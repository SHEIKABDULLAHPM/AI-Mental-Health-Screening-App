package com.mindease.backend.features.journal.api;

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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.journal.application.JournalService;
import com.mindease.backend.features.journal.dto.CreateJournalRequest;
import com.mindease.backend.features.journal.dto.JournalListResponse;
import com.mindease.backend.features.journal.dto.JournalResponse;
import com.mindease.backend.features.journal.dto.UpdateJournalRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/journals")
public class JournalController {

    private final JournalService service;

    public JournalController(JournalService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<JournalResponse>> create(
            @Valid @RequestBody CreateJournalRequest request) {
        String userId = AuthenticatedUser.currentId();
        JournalResponse response = service.createJournal(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<JournalListResponse>> list(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String type,
            @RequestParam(required = false) String search) {
        String userId = AuthenticatedUser.currentId();
        JournalListResponse list = service.getJournalEntries(userId, page, size, type, search);
        return ResponseEntity.ok(ApiResponse.ok(list));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<JournalResponse>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getJournalById(userId, id)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<JournalResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody UpdateJournalRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.updateJournal(userId, id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        service.deleteJournal(userId, id);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    /**
     * Retry AI analysis for a journal entry that failed or is stale.
     */
    @PostMapping("/{id}/analysis/retry")
    public ResponseEntity<ApiResponse<JournalResponse>> retryAnalysis(
            @PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.retryAiAnalysis(userId, id)));
    }
}
