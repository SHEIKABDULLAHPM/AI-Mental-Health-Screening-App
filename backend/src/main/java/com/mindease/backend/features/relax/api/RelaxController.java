package com.mindease.backend.features.relax.api;

import java.util.List;
import java.util.Optional;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.features.relax.application.RelaxService;
import com.mindease.backend.features.relax.dto.RelaxActivityResponse;
import com.mindease.backend.security.AuthenticatedUser;

@RestController
@RequestMapping("/api/v1/relax")
public class RelaxController {

    private final RelaxService service;

    public RelaxController(RelaxService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<List<RelaxActivityResponse>>> getActivities(
            @RequestParam(required = false) Optional<String> category) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getActivities(userId, category)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<ApiResponse<RelaxActivityResponse>> getActivityById(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        return ResponseEntity.ok(ApiResponse.ok(service.getActivityById(userId, id)));
    }

    @PostMapping("/{id}/complete")
    public ResponseEntity<ApiResponse<RelaxActivityResponse>> completeActivity(@PathVariable String id) {
        String userId = AuthenticatedUser.currentId();
        RelaxActivityResponse response = service.completeActivity(userId, id);
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(response));
    }
}
