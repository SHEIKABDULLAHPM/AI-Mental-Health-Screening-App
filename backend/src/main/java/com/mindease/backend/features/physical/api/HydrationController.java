package com.mindease.backend.features.physical.api;

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
import com.mindease.backend.features.physical.application.HydrationService;
import com.mindease.backend.features.physical.dto.HydrationDtos;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

/**
 * Hydration logging. Identity always comes from the JWT context; entry
 * ownership is enforced per mutation.
 */
@RestController
@RequestMapping("/api/v1/physical/hydration")
public class HydrationController {

    private final HydrationService hydration;

    public HydrationController(HydrationService hydration) {
        this.hydration = hydration;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<HydrationDtos.HydrationResponse>> overview(
            @RequestParam(required = false) Integer days) {
        return ResponseEntity.ok(ApiResponse.ok(
                hydration.overview(AuthenticatedUser.currentId(), days)));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<HydrationDtos.EntryResponse>> add(
            @Valid @RequestBody HydrationDtos.HydrationRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(
                hydration.add(AuthenticatedUser.currentId(), request)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<HydrationDtos.EntryResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody HydrationDtos.HydrationRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(
                hydration.update(AuthenticatedUser.currentId(), id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable String id) {
        hydration.delete(AuthenticatedUser.currentId(), id);
        return ResponseEntity.ok(ApiResponse.ok());
    }

    @PutMapping("/target")
    public ResponseEntity<ApiResponse<HydrationDtos.HydrationResponse>> updateTarget(
            @Valid @RequestBody HydrationDtos.HydrationTargetRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(
                hydration.updateTarget(AuthenticatedUser.currentId(), request.targetMl())));
    }
}
