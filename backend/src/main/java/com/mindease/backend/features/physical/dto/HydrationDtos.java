package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Hydration logging contract. Amounts are normalised to millilitres server-side
 * so daily totals never mix units.
 */
public final class HydrationDtos {

    private HydrationDtos() {
    }

    public record HydrationRequest(
            @NotNull(message = "amount is required")
            // Bounds are deliberately unit-agnostic: 0.5 l is a valid 500 ml
            // entry, so the minimum allows a fractional litre. The exact,
            // unit-aware ceiling is enforced by LifestyleUnits after conversion.
            @DecimalMin(value = "0.001", message = "amount must be greater than zero")
            @DecimalMax(value = "5000", message = "a single entry cannot exceed 5000 ml")
            Double amount,
            @Size(max = 16) String unit,
            Instant timestamp) {
    }

    public record HydrationTargetRequest(
            @NotNull(message = "target is required")
            @DecimalMin(value = "250", message = "target must be at least 250 ml")
            @DecimalMax(value = "10000", message = "target must be at most 10000 ml")
            Integer targetMl) {
    }

    public record EntryResponse(
            String id,
            LocalDate date,
            double amountMl,
            Instant timestamp,
            String source) {
    }

    public record DayResponse(
            LocalDate date,
            double totalMl,
            int entryCount,
            List<EntryResponse> entries) {
    }

    public record HydrationResponse(
            String unit,
            Integer targetMl,
            boolean targetCustomized,
            DayResponse today,
            List<DayResponse> days,
            String guidance) {
    }
}
