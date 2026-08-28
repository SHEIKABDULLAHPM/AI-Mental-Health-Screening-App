package com.mindease.backend.coach.api;

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
import com.mindease.backend.coach.application.CoachService;
import com.mindease.backend.coach.application.ConversationService;
import com.mindease.backend.coach.dto.ConversationResponse;
import com.mindease.backend.coach.dto.CreateConversationRequest;
import com.mindease.backend.coach.dto.MessageResponse;
import com.mindease.backend.coach.dto.SendMessageRequest;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/conversations")
public class CoachController {

    private final ConversationService conversationService;
    private final CoachService coachService;

    public CoachController(ConversationService conversationService, CoachService coachService) {
        this.conversationService = conversationService;
        this.coachService = coachService;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<ConversationResponse>> createConversation(
            @Valid @RequestBody(required = false) CreateConversationRequest request) {
        String userId = AuthenticatedUser.currentId();
        var req = request != null ? request : new CreateConversationRequest(null);
        ConversationResponse response = conversationService.createConversation(userId, req);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<ConversationResponse>>> listConversations(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        String userId = AuthenticatedUser.currentId();
        List<ConversationResponse> conversations = conversationService.getConversations(userId, page, size);
        return ResponseEntity.ok(ApiResponse.ok(conversations));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<ConversationResponse>> getConversation(
            @PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        ConversationResponse response = conversationService.getConversation(userId, id);
        return ResponseEntity.ok(ApiResponse.ok(response));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> deleteConversation(
            @PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        conversationService.deleteConversation(userId, id);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    @GetMapping("/{id}/messages")
    public ResponseEntity<ApiResponse<List<MessageResponse>>> getMessages(
            @PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        List<MessageResponse> messages = conversationService.getMessages(userId, id);
        return ResponseEntity.ok(ApiResponse.ok(messages));
    }

    @PostMapping("/{id}/messages")
    public ResponseEntity<ApiResponse<MessageResponse>> sendMessage(
            @PathVariable String id,
            @Valid @RequestBody SendMessageRequest request) {
        String userId = AuthenticatedUser.currentId();
        // This triggers the full coach pipeline: context → safety → RAG → Gemini → persist
        MessageResponse response = coachService.processMessage(userId, id, request.message());
        return ResponseEntity.ok(ApiResponse.ok(response));
    }
}
