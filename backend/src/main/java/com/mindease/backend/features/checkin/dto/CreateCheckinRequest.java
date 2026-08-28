package com.mindease.backend.features.checkin.dto;

import java.util.List;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

public record CreateCheckinRequest(
        @NotNull @Min(1) @Max(5) Integer mood,
        @NotNull @Min(1) @Max(5) Integer sleep,
        @NotNull @Min(1) @Max(5) Integer energy,
        @NotNull @Min(1) @Max(5) Integer stress,
        List<String> activities) {
}
