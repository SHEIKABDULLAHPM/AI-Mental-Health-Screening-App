package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.features.physical.domain.BodyMeasurement;
import com.mindease.backend.features.physical.domain.BodyMeasurementRepository;
import com.mindease.backend.features.physical.domain.MeasurementType;
import com.mindease.backend.features.physical.dto.BodyMeasurementDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Manual (and verified external) body measurements.
 *
 * <p>BMI is computed only when both a real weight and height exist, and is
 * always returned with its category and a disclaimer. Composition metrics are
 * never inferred.</p>
 */
@Service
public class BodyMeasurementService {

    static final int MAX_HISTORY = 60;
    static final int DEFAULT_HISTORY = 30;
    static final int TREND_WINDOW_DAYS = 30;

    private static final String BMI_DISCLAIMER =
            "BMI is a limited population-level screening measure. It does not measure "
                    + "body-fat percentage, muscle mass or health status and is not a diagnosis.";

    private final BodyMeasurementRepository measurements;
    private final LifestyleUnits units;

    public BodyMeasurementService(BodyMeasurementRepository measurements, LifestyleUnits units) {
        this.measurements = measurements;
        this.units = units;
    }

    public BodyMeasurementDtos.BodySummaryResponse overview(String userId, Integer limitParam) {
        int limit = limitParam == null ? DEFAULT_HISTORY : limitParam;
        limit = Math.min(Math.max(limit, 1), MAX_HISTORY);

        List<BodyMeasurement> history = measurements
                .findByUserIdOrderByMeasuredAtDesc(userId, PageRequest.of(0, limit));
        List<BodyMeasurementDtos.MeasurementResponse> mapped = new ArrayList<>();
        for (BodyMeasurement row : history) {
            mapped.add(map(row));
        }

        Optional<BodyMeasurement> latestWeight =
                measurements.findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(userId);
        Optional<BodyMeasurement> latestHeight =
                measurements.findFirstByUserIdAndHeightCmNotNullOrderByMeasuredAtDesc(userId);

        BodyMeasurementDtos.BmiBlock bmi = null;
        if (latestWeight.isPresent() && latestHeight.isPresent()) {
            double weightKg = latestWeight.get().getWeightKg();
            double heightCm = latestHeight.get().getHeightCm();
            double heightM = heightCm / 100d;
            if (heightM > 0) {
                double value = Math.round((weightKg / (heightM * heightM)) * 10d) / 10d;
                String category = units.bmiCategory(value);
                bmi = new BodyMeasurementDtos.BmiBlock(
                        value,
                        category,
                        units.bmiLabel(category),
                        BMI_DISCLAIMER,
                        weightKg,
                        heightCm,
                        latestHeight.get().getMeasuredAt().isAfter(latestWeight.get().getMeasuredAt())
                                ? latestHeight.get().getMeasuredAt()
                                : latestWeight.get().getMeasuredAt());
            }
        }

        BodyMeasurementDtos.WeightTrend trend = weightTrend(userId);

        return new BodyMeasurementDtos.BodySummaryResponse(
                "kg",
                "cm",
                history.isEmpty() ? null : mapped.get(0),
                bmi,
                trend,
                mapped,
                List.of(
                        BMI_DISCLAIMER,
                        "Body-fat percentage and muscle mass are not shown because no "
                                + "verified measurement source provides them."));
    }

    public BodyMeasurementDtos.MeasurementResponse add(
            String userId, BodyMeasurementDtos.BodyMeasurementRequest request) {
        Double weightKg = request.weight() == null
                ? null : units.weightToKg(request.weight(), request.weightUnit());
        Double heightCm = request.height() == null
                ? null : units.heightToCm(request.height(), request.heightUnit());
        if (weightKg == null && heightCm == null) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Provide a weight, a height or both");
        }
        Instant measuredAt = request.measuredAt() == null ? Instant.now() : request.measuredAt();
        if (measuredAt.isAfter(Instant.now().plusSeconds(300))) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Measurement time cannot be in the future");
        }
        Instant now = Instant.now();
        BodyMeasurement measurement = new BodyMeasurement();
        measurement.setUserId(userId);
        measurement.setWeightKg(weightKg);
        measurement.setHeightCm(heightCm);
        measurement.setMeasuredAt(measuredAt);
        measurement.setDate(measuredAt.atZone(zone()).toLocalDate());
        measurement.setSource(MeasurementType.USER_ENTERED);
        measurement.setCreatedAt(now);
        measurement.setUpdatedAt(now);
        return map(measurements.save(measurement));
    }

    public BodyMeasurementDtos.MeasurementResponse update(
            String userId, String measurementId,
            BodyMeasurementDtos.BodyMeasurementRequest request) {
        BodyMeasurement measurement = measurements.findByIdAndUserId(measurementId, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND, "Body measurement not found"));
        Double weightKg = request.weight() == null
                ? measurement.getWeightKg()
                : units.weightToKg(request.weight(), request.weightUnit());
        Double heightCm = request.height() == null
                ? measurement.getHeightCm()
                : units.heightToCm(request.height(), request.heightUnit());
        if (weightKg == null && heightCm == null) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Provide a weight, a height or both");
        }
        measurement.setWeightKg(weightKg);
        measurement.setHeightCm(heightCm);
        if (request.measuredAt() != null) {
            if (request.measuredAt().isAfter(Instant.now().plusSeconds(300))) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Measurement time cannot be in the future");
            }
            measurement.setMeasuredAt(request.measuredAt());
            measurement.setDate(request.measuredAt().atZone(zone()).toLocalDate());
        }
        measurement.setUpdatedAt(Instant.now());
        return map(measurements.save(measurement));
    }

    public void delete(String userId, String measurementId) {
        BodyMeasurement measurement = measurements.findByIdAndUserId(measurementId, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND, "Body measurement not found"));
        measurements.delete(measurement);
    }

    /** Latest weight, or {@code null} when the user never recorded one. */
    public Double latestWeightKg(String userId) {
        return measurements.findFirstByUserIdAndWeightKgNotNullOrderByMeasuredAtDesc(userId)
                .map(BodyMeasurement::getWeightKg)
                .orElse(null);
    }

    private BodyMeasurementDtos.WeightTrend weightTrend(String userId) {
        ZoneId zone = zone();
        Instant from = LocalDate.now(zone).minusDays(TREND_WINDOW_DAYS)
                .atStartOfDay(zone).toInstant();
        List<BodyMeasurement> rows =
                measurements.findByUserIdAndMeasuredAtBetweenOrderByMeasuredAtDesc(
                        userId, from, Instant.now());
        List<BodyMeasurement> withWeight = rows.stream()
                .filter(row -> row.getWeightKg() != null)
                .toList();
        if (withWeight.isEmpty()) {
            return new BodyMeasurementDtos.WeightTrend(null, null, null, 0, TREND_WINDOW_DAYS);
        }
        Double latest = withWeight.get(0).getWeightKg();
        Double previous = withWeight.size() > 1 ? withWeight.get(1).getWeightKg() : null;
        Double change = previous == null ? null
                : Math.round((latest - previous) * 100d) / 100d;
        return new BodyMeasurementDtos.WeightTrend(
                latest, previous, change, withWeight.size(), TREND_WINDOW_DAYS);
    }

    private BodyMeasurementDtos.MeasurementResponse map(BodyMeasurement row) {
        return new BodyMeasurementDtos.MeasurementResponse(
                row.getId(),
                row.getDate(),
                row.getWeightKg(),
                row.getHeightCm(),
                row.getMeasuredAt(),
                row.getSource() == null ? "USER_ENTERED" : row.getSource().name(),
                row.getDeviceId());
    }

    private static ZoneId zone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }
}
