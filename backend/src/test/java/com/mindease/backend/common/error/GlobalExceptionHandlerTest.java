package com.mindease.backend.common.error;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * An unknown route must be a 404. It previously fell through to the generic
 * handler and answered 500, so a mistyped or trailing-slash URL looked like a
 * backend outage.
 */
class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void unknownRouteIsNotFoundNotInternalServerError() {
        ResponseEntity<Map<String, Object>> response = handler.handleNoResource(
                new NoResourceFoundException(HttpMethod.GET, "api/v1/wellness-profile/"));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).containsEntry("error", "NOT_FOUND");
        assertThat(response.getBody()).containsEntry("status", 404);
    }
}
