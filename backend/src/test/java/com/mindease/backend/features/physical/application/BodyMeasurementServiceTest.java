package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.physical.domain.BodyMeasurement;
import com.mindease.backend.features.physical.domain.BodyMeasurementRepository;
import com.mindease.backend.features.physical.dto.BodyMeasurementDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Weight/BMI contract: BMI only exists when both real inputs exist, composition
 * values are never inferred, and the record is always labelled as a screening
 * measure rather than a diagnosis.
 */
@ExtendWith(MockitoExtension.class)
class BodyMeasurementServiceTest {

    private static final String USER = "user-a";

    @Mock
    private BodyMeasurementRepository measurements;

    private BodyMeasurementService service;

    @BeforeEach
    void setUp() {
        UserTimeZoneHolder.set("UTC");
        service = new BodyMeasurementService(measurements, new LifestyleUnits());
        lenient().when(measurements.save(any(BodyMeasurement.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @AfterEach
    void tearDown() {
        UserTimeZoneHolder.clear();
    }

    private BodyMeasurement row(String id, Double weightKg, Double heightCm, Instant at) {
        BodyMeasurement row = new BodyMeasurement();
        row.setId(id);
        row.setUserId(USER);
        row.setWeightKg(weightKg);
        row.setHeightCm(heightCm);
        row.setMeasuredAt(at);
        row.setDate(at.atZone(ZoneOffset.UTC).toLocalDate());
        return row;
    }

    @Test
    void add_convertsPoundsToKilograms() {
        var response = service.add(USER, new BodyMeasurementDtos.BodyMeasurementRequest(
                154.324d, null, "lb", null, null));

        ArgumentCaptor<BodyMeasurement> saved = ArgumentCaptor.forClass(BodyMeasurement.class);
        verify(measurements).save(saved.capture());
        assertThat(saved.getValue().getWeightKg()).isCloseTo(70d,
                org.assertj.core.data.Offset.offset(0.01d));
        assertThat(saved.getValue().getHeightCm()).isNull();
        assertThat(response.source()).isEqualTo("USER_ENTERED");
    }

    @Test
    void add_requiresAtLeastOneValue() {
        assertThatThrownBy(() -> service.add(USER, new BodyMeasurementDtos.BodyMeasurementRequest(
                null, null, null, null, null)))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.BAD_REQUEST);
        verify(measurements, never()).save(any(BodyMeasurement.class));
    }

    @Test
    void add_rejectsFutureMeasurementTime() {
        assertThatThrownBy(() -> service.add(USER, new BodyMeasurementDtos.BodyMeasurementRequest(
                70d, null, "kg", null, Instant.now().plusSeconds(3600))))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("future");
    }

    @Test
    void overview_computesBmiOnlyWhenWeightAndHeightBothExist() {
        Instant now = Instant.now();
        BodyMeasurement weight = row("m1", 70d, null, now);
        when(measurements.findByUserIdOrderByMeasuredAtDesc(eq(USER), any()))
                .thenReturn(List.of(weight));
        when(measurements.findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.of(weight));
        when(measurements.findFirstByUserIdAndHeightCmNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.empty());
        when(measurements.findByUserIdAndMeasuredAtBetweenOrderByMeasuredAtDesc(any(), any(), any()))
                .thenReturn(List.of(weight));

        var summary = service.overview(USER, null);

        assertThat(summary.bmi()).isNull();
        assertThat(summary.latest().weightKg()).isEqualTo(70d);
    }

    @Test
    void overview_reportsBmiAsScreeningMeasureWithDisclaimer() {
        Instant now = Instant.now();
        BodyMeasurement weight = row("m1", 81d, null, now);
        BodyMeasurement height = row("m2", null, 180d, now.minusSeconds(3600));
        when(measurements.findByUserIdOrderByMeasuredAtDesc(eq(USER), any()))
                .thenReturn(List.of(weight, height));
        when(measurements.findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.of(weight));
        when(measurements.findFirstByUserIdAndHeightCmNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.of(height));
        when(measurements.findByUserIdAndMeasuredAtBetweenOrderByMeasuredAtDesc(any(), any(), any()))
                .thenReturn(List.of(weight));

        var summary = service.overview(USER, 30);

        assertThat(summary.bmi()).isNotNull();
        assertThat(summary.bmi().value()).isEqualTo(25d);
        assertThat(summary.bmi().category()).isEqualTo("ABOVE_REFERENCE_RANGE");
        assertThat(summary.bmi().disclaimer()).containsIgnoringCase("not a diagnosis");
        assertThat(summary.bmi().weightKg()).isEqualTo(81d);
        assertThat(summary.bmi().heightCm()).isEqualTo(180d);
        assertThat(summary.limitations())
                .anyMatch(note -> note.contains("Body-fat percentage"));
    }

    @Test
    void overview_trendComparesLatestTwoWeights() {
        Instant now = Instant.now();
        BodyMeasurement newest = row("m2", 72d, null, now);
        BodyMeasurement previous = row("m1", 74d, null, now.minusSeconds(86_400));
        when(measurements.findByUserIdOrderByMeasuredAtDesc(eq(USER), any()))
                .thenReturn(List.of(newest, previous));
        when(measurements.findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.of(newest));
        when(measurements.findFirstByUserIdAndHeightCmNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.empty());
        when(measurements.findByUserIdAndMeasuredAtBetweenOrderByMeasuredAtDesc(any(), any(), any()))
                .thenReturn(List.of(newest, previous));

        var summary = service.overview(USER, null);

        assertThat(summary.trend().latestKg()).isEqualTo(72d);
        assertThat(summary.trend().previousKg()).isEqualTo(74d);
        assertThat(summary.trend().changeKg()).isEqualTo(-2d);
        assertThat(summary.trend().daysWithData()).isEqualTo(2);
    }

    @Test
    void update_andDelete_enforceOwnership() {
        when(measurements.findByIdAndUserId("m9", USER)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.update(USER, "m9",
                new BodyMeasurementDtos.BodyMeasurementRequest(70d, null, "kg", null, null)))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
        assertThatThrownBy(() -> service.delete(USER, "m9"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    @Test
    void latestWeight_isNullWhenNoMeasurementExists() {
        when(measurements.findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(USER))
                .thenReturn(Optional.empty());

        assertThat(service.latestWeightKg(USER)).isNull();
    }

    @Test
    void responseModelExposesNoCompositionFields() {
        // Guard rail: the DTO must not grow body-fat/muscle-mass fields without
        // a verified measurement source behind them.
        assertThat(BodyMeasurementDtos.MeasurementResponse.class.getRecordComponents())
                .extracting(java.lang.reflect.RecordComponent::getName)
                .containsExactlyInAnyOrder(
                        "id", "date", "weightKg", "heightCm", "measuredAt", "source", "deviceId");
    }
}
