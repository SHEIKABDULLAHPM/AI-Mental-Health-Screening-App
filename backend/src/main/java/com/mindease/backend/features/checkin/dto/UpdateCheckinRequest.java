package com.mindease.backend.features.checkin.dto;

import java.util.List;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

public record UpdateCheckinRequest(
        @Min(1) @Max(5) Integer mood,
        @Min(1) @Max(5) Integer sleep,
        @Min(1) @Max(5) Integer energy,
        @Min(1) @Max(5) Integer stress,
        List<String> activities) {
}
