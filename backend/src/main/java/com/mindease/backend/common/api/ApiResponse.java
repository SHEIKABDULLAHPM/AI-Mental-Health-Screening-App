package com.mindease.backend.common.api;

import java.time.Instant;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Uniform envelope for all successful REST responses.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiResponse<T>(boolean success, T data, Instant timestamp, String message) {

    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(true, data, Instant.now(), null);
    }

    public static ApiResponse<Void> ok() {
        return new ApiResponse<>(true, null, Instant.now(), null);
    }

    public static <T> ApiResponse<T> created(T data) {
        return new ApiResponse<>(true, data, Instant.now(), null);
    }
}