package com.mindease.backend.screening.api;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import jakarta.validation.Valid;import com.mindease.backend.screening.application.QuestionnaireCatalogService;
import com.mindease.backend.screening.application.ScreeningService;
import com.mindease.backend.screening.domain.QuestionnaireCatalog;
import com.mindease.backend.screening.domain.Screening;
import com.mindease.backend.screening.dto.ScreeningSubmitResponse;
import com.mindease.backend.security.AuthenticatedUser;

/**
 * Assessment endpoints. All ids sent by the client are scoped to the
 * authenticated user server-side.
 */
@RestController
@RequestMapping("/api/v1/screenings")
public class ScreeningController {

    private final ScreeningService service;
    private final QuestionnaireCatalogService catalogService;

    public ScreeningController(ScreeningService service, QuestionnaireCatalogService catalogService) {
        this.service = service;
        this.catalogService = catalogService;
    }

    @GetMapping("/questions")
    public ResponseEntity<ApiResponse<QuestionnaireCatalog>> questions() {
        return ResponseEntity.ok(ApiResponse.ok(catalogService.current()));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<Screening>> create(@Valid @RequestBody Screening draft) {
        String userId = AuthenticatedUser.currentId();
        ScreeningService.CreateResult result = service.create(userId, draft);
        return (result.created()
                ? ResponseEntity.status(HttpStatus.CREATED)
                : ResponseEntity.ok())
                .body(ApiResponse.ok(result.screening()));
    }

    @GetMapping("/me")
    public ResponseEntity<ApiResponse<List<Screening>>> mine() {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.mine(userId)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<Screening>> getById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getById(userId, id)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<Screening>> update(
            @PathVariable String id, @Valid @RequestBody Screening draft) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.update(userId, id, draft)));
    }

    @PostMapping("/{id}/submit")
    public ResponseEntity<ApiResponse<ScreeningSubmitResponse>> submit(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.submit(userId, id)));
    }
}