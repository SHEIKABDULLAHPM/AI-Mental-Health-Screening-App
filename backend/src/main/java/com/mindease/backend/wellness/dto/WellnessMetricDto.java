package com.mindease.backend.wellness.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * One numeric aggregate sent to the AI service and stored for comparison.
 *
 * <p>Only numbers the user already sees in the app are ever placed here: no
 * identifiers, journal text or raw wearable samples.</p>
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record WellnessMetricDto(String key, String label, double value, String unit) {
}
