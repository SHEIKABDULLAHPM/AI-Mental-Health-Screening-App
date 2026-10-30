package com.mindease.backend.wellness.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * One actionable suggestion with its own title and explanation.
 *
 * <p>{@code recommendations} on the analysis responses stays a plain string
 * list for backwards compatibility; this structured form is what the app
 * renders so a long description is not crammed into one line.</p>
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record WellnessAdviceDto(String title, String description, String category) {
}
