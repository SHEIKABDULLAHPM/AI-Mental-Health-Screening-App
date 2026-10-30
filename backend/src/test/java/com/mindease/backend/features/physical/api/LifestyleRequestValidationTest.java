package com.mindease.backend.features.physical.api;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Set;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.error.GlobalExceptionHandler;
import com.mindease.backend.features.physical.dto.BodyMeasurementDtos;
import com.mindease.backend.features.physical.dto.HydrationDtos;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;

/**
 * Request-contract checks for the unit-aware lifestyle payloads.
 *
 * <p>Bean validation must not reject a value just because it is expressed in a
 * larger unit (0.5 l is 500 ml), and the unit layer's rejection of an unknown
 * unit or an out-of-range normalised value must surface as a 400, not a 500.</p>
 */
class LifestyleRequestValidationTest {

    private final Validator validator =
            Validation.buildDefaultValidatorFactory().getValidator();

    @Test
    void hydrationAcceptsAValidAmountExpressedInLitres() {
        Set<ConstraintViolation<HydrationDtos.HydrationRequest>> violations =
                validator.validate(new HydrationDtos.HydrationRequest(0.5d, "l", null));

        assertThat(violations).isEmpty();
    }

    @Test
    void hydrationStillRequiresAnAmount() {
        Set<ConstraintViolation<HydrationDtos.HydrationRequest>> violations =
                validator.validate(new HydrationDtos.HydrationRequest(null, "ml", null));

        assertThat(violations)
                .extracting(v -> v.getPropertyPath().toString())
                .contains("amount");
    }

    @Test
    void bodyMeasurementAcceptsImperialInputAndValidatesAfterConversion() {
        Set<ConstraintViolation<BodyMeasurementDtos.BodyMeasurementRequest>> violations =
                validator.validate(new BodyMeasurementDtos.BodyMeasurementRequest(
                        160d, 70d, "lb", "in", null));

        // 160 lb ≈ 72.6 kg, 70 in ≈ 177.8 cm: both are valid once converted.
        assertThat(violations).isEmpty();
    }

    @Test
    void unitLayerRejectionsMapToAClientError() {
        var handler = new GlobalExceptionHandler();

        var response = handler.handleIllegalArgument(
                new IllegalArgumentException("Unsupported hydration unit: bucket"));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody())
                .containsEntry("status", 400)
                .containsEntry("error", ErrorCode.VALIDATION_FAILED.name())
                .containsEntry("message", "Unsupported hydration unit: bucket");
    }
}
