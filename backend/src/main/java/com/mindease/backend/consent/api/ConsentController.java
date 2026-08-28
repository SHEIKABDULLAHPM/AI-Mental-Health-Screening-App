package com.mindease.backend.consent.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.consent.application.ConsentService;
import com.mindease.backend.consent.dto.ConsentRequest;
import com.mindease.backend.consent.dto.ConsentResponse;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/v1/consent")
public class ConsentController {

    private final ConsentService service;

    public ConsentController(ConsentService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<ConsentResponse>> get() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.myConsents(userId)));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<ConsentResponse>> accept(
            @Valid @RequestBody ConsentRequest request) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.accept(userId, request)));
    }
}