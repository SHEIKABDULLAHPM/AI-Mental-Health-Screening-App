package com.mindease.backend.features.physical.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.data.mongodb.repository.Query;

/**
 * Guards the inclusive date-range queries.
 *
 * <p>Spring Data MongoDB derives {@code Between} as {@code $gt}/{@code $lt}
 * (exclusive), which made today's entries invisible in today's totals. These
 * repositories therefore declare explicit {@code $gte}/{@code $lte} queries;
 * this test fails if one is ever reverted to the derived keyword.</p>
 */
class RepositoryRangeQueryContractTest {

    private static void assertInclusiveRange(Class<?> repository, String method,
                                             Class<?>... parameters) throws Exception {
        Query query = repository.getMethod(method, parameters).getAnnotation(Query.class);
        assertThat(query)
                .as("%s.%s must declare an explicit range query", repository.getSimpleName(), method)
                .isNotNull();
        assertThat(query.value())
                .as("%s.%s lower bound", repository.getSimpleName(), method)
                .contains("$gte");
        assertThat(query.value())
                .as("%s.%s upper bound", repository.getSimpleName(), method)
                .contains("$lte");
    }

    @Test
    void hydrationRangeIncludesBothBoundaryDays() throws Exception {
        assertInclusiveRange(HydrationEntryRepository.class,
                "findByUserIdAndDateBetweenOrderByDateDesc",
                String.class, java.time.LocalDate.class, java.time.LocalDate.class);
    }

    @Test
    void dailyActivityRangeIncludesBothBoundaryDays() throws Exception {
        assertInclusiveRange(DailyActivityRepository.class,
                "findByUserIdAndDateBetweenOrderByDateDesc",
                String.class, java.time.LocalDate.class, java.time.LocalDate.class);
    }

    @Test
    void bodyMeasurementRangeIncludesBothBoundaryInstants() throws Exception {
        assertInclusiveRange(BodyMeasurementRepository.class,
                "findByUserIdAndMeasuredAtBetweenOrderByMeasuredAtDesc",
                String.class, java.time.Instant.class, java.time.Instant.class);
    }

    @Test
    void healthReadingRangeIncludesBothBoundaryInstants() throws Exception {
        assertInclusiveRange(HealthReadingRepository.class,
                "findByUserIdAndMetricTypeAndTimestampBetweenOrderByTimestampDesc",
                String.class, HealthMetricType.class,
                java.time.Instant.class, java.time.Instant.class);
    }

    @Test
    void sleepRangeIncludesBothBoundaryInstants() throws Exception {
        assertInclusiveRange(SleepSessionRepository.class,
                "findByUserIdAndStartTimeBetweenOrderByStartTimeDesc",
                String.class, java.time.Instant.class, java.time.Instant.class);
    }

    @Test
    void dailyCheckinRangeIncludesBothBoundaryDays() throws Exception {
        assertInclusiveRange(com.mindease.backend.features.checkin.domain.DailyCheckinRepository.class,
                "findByUserIdAndDateBetweenOrderByDateAsc",
                String.class, java.time.LocalDate.class, java.time.LocalDate.class);
    }

    @Test
    void exerciseRangeIncludesBothBoundaryInstants() throws Exception {
        assertInclusiveRange(ExerciseSessionRepository.class,
                "findByUserIdAndStartTimeBetweenOrderByStartTimeDesc",
                String.class, java.time.Instant.class, java.time.Instant.class);
    }
}
