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
import com.mindease.backend.features.physical.application.BodyMeasurementService;
import com.mindease.backend.features.physical.dto.BodyMeasurementDtos;
import com.mindease.backend.security.AuthenticatedUser;

import jakarta.validation.Valid;

/** Weight/height entry, history and the clearly-labelled BMI screening block. */
@RestController
@RequestMapping("/api/v1/physical/body")
public class BodyMeasurementController {

    private final BodyMeasurementService measurements;

    public BodyMeasurementController(BodyMeasurementService measurements) {
        this.measurements = measurements;
    }

    @GetMapping
    public ResponseEntity<ApiResponse<BodyMeasurementDtos.BodySummaryResponse>> overview(
            @RequestParam(required = false) Integer limit) {
        return ResponseEntity.ok(ApiResponse.ok(
                measurements.overview(AuthenticatedUser.currentId(), limit)));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<BodyMeasurementDtos.MeasurementResponse>> add(
            @Valid @RequestBody BodyMeasurementDtos.BodyMeasurementRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.created(
                measurements.add(AuthenticatedUser.currentId(), request)));
    }

    @PutMapping("/{id}")
    public ResponseEntity<ApiResponse<BodyMeasurementDtos.MeasurementResponse>> update(
            @PathVariable String id,
            @Valid @RequestBody BodyMeasurementDtos.BodyMeasurementRequest request) {
        return ResponseEntity.ok(ApiResponse.ok(
                measurements.update(AuthenticatedUser.currentId(), id, request)));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<ApiResponse<Void>> delete(@PathVariable String id) {
        measurements.delete(AuthenticatedUser.currentId(), id);
        return ResponseEntity.ok(ApiResponse.ok());
    }
}
