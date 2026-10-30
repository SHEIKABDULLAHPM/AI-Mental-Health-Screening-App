package com.mindease.backend.common.error;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

/**
 * Centralized error handling: maps exceptions to a consistent JSON body.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<Map<String, Object>> handleApiException(ApiException ex) {
        log.warn("ApiException: {} - {}", ex.getCodeName(), ex.getMessage());
        return build(ex.getStatus(), ex.getCodeName(), ex.getMessage(), null);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> fields = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors()
                .forEach(fe -> fields.putIfAbsent(fe.getField(), fe.getDefaultMessage()));
        log.warn("Validation failed on {}", fields);
        return build(HttpStatus.BAD_REQUEST, ErrorCode.VALIDATION_FAILED.name(), "Invalid request", fields);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<Map<String, Object>> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return build(HttpStatus.BAD_REQUEST, ErrorCode.BAD_REQUEST.name(),
                String.format("Invalid value for '%s'", ex.getName()), null);
    }

    /** Malformed or unparseable request bodies are client errors, not 500s. */
    @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, Object>> handleUnreadableBody(
            org.springframework.http.converter.HttpMessageNotReadableException ex) {
        log.warn("Unreadable request body: {}", ex.getMessage());
        return build(HttpStatus.BAD_REQUEST, ErrorCode.VALIDATION_FAILED.name(),
                "Invalid request body", null);
    }

    /**
     * Unit-aware value checks (litres, pounds, inches…) happen after the raw
     * payload is parsed, so they surface as {@link IllegalArgumentException}.
     * They are still client errors: map them to 400 instead of a generic 500.
     * The message is a validation sentence from the unit/validator layer and
     * never contains request secrets.
     */
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalArgument(
            IllegalArgumentException ex) {
        log.warn("Rejected request value: {}", ex.getMessage());
        String message = ex.getMessage() == null
                ? "Invalid value" : ex.getMessage();
        return build(HttpStatus.BAD_REQUEST, ErrorCode.VALIDATION_FAILED.name(),
                message, null);
    }

    /**
     * An unknown route (including a trailing slash such as
     * {@code /api/v1/wellness-profile/}) is a client error. Without this
     * mapping Spring's {@code NoResourceFoundException} fell into the generic
     * handler and answered 500, which made a simple wrong URL look like a
     * server outage.
     */
    @ExceptionHandler(org.springframework.web.servlet.resource.NoResourceFoundException.class)
    public ResponseEntity<Map<String, Object>> handleNoResource(
            org.springframework.web.servlet.resource.NoResourceFoundException ex) {
        return build(HttpStatus.NOT_FOUND, ErrorCode.NOT_FOUND.name(),
                "Resource not found", null);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleGeneric(Exception ex) {
        log.error("Unhandled exception", ex);
        return build(HttpStatus.INTERNAL_SERVER_ERROR, ErrorCode.INTERNAL_ERROR.name(),
                "Internal server error", null);
    }

    private ResponseEntity<Map<String, Object>> build(HttpStatus status, String code,
                                                      String message, Map<String, String> details) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("timestamp", Instant.now());
        body.put("status", status.value());
        body.put("error", code);
        body.put("message", message);
        if (details != null && !details.isEmpty()) {
            body.put("details", details);
        }
        return ResponseEntity.status(status).body(body);
    }
}