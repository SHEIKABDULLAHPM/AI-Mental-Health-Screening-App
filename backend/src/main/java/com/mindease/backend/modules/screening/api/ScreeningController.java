package com.mindease.backend.modules.screening.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.modules.screening.application.ScreeningService;
import com.mindease.backend.modules.screening.domain.Screening;

import jakarta.validation.Valid;

/**
 * REST entry points for screening. All endpoints are /api/v1/...
 */
@RestController
@RequestMapping("/api/v1/screenings")
public class ScreeningController {

    private final ScreeningService service;

    public ScreeningController(ScreeningService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<ApiResponse<Screening>> submit(@Valid @RequestBody Screening screening) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(service.submit(screening)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<Screening>> getById(@PathVariable String id) {
        return ResponseEntity.ok(ApiResponse.ok(service.getById(id)));
    }

    @GetMapping("/me")
    public ResponseEntity<ApiResponse<List<Screening>>> mine(Authentication authentication) {
        String userId = authentication.getName();
        return ResponseEntity.ok(ApiResponse.ok(service.forUser(userId)));
    }
}