package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import jakarta.validation.constraints.Size;

/**
 * Body measurement contract. Weights are stored in kilograms and heights in
 * centimetres; imperial input is converted server-side.
 */
public final class BodyMeasurementDtos {

    private BodyMeasurementDtos() {
    }

    public record BodyMeasurementRequest(
            Double weight,
            Double height,
            @Size(max = 16) String weightUnit,
            @Size(max = 16) String heightUnit,
            Instant measuredAt) {
    }

    public record MeasurementResponse(
            String id,
            LocalDate date,
            Double weightKg,
            Double heightCm,
            Instant measuredAt,
            String source,
            String deviceId) {
    }

    /**
     * BMI is a limited screening number, not a diagnosis. The record carries
     * its own disclaimer and the exact inputs it was calculated from so the UI
     * can label it honestly.
     */
    public record BmiBlock(
            double value,
            String category,
            String label,
            String disclaimer,
            Double weightKg,
            Double heightCm,
            Instant calculatedFrom) {
    }

    public record WeightTrend(
            Double latestKg,
            Double previousKg,
            Double changeKg,
            int daysWithData,
            int windowDays) {
    }

    public record BodySummaryResponse(
            String weightUnit,
            String heightUnit,
            MeasurementResponse latest,
            BmiBlock bmi,
            WeightTrend trend,
            List<MeasurementResponse> history,
            List<String> limitations) {
    }
}
