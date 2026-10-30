package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * Sleep history. Stage data is not part of this response until it has been
 * verified on the target firmware.
 */
public record SleepHistoryResponse(
        boolean available,
        Session latest,
        List<Session> sessions) {

    public record Session(
            LocalDate date,
            Instant startTime,
            Instant endTime,
            Long durationMillis) {
    }

    public static SleepHistoryResponse empty() {
        return new SleepHistoryResponse(false, null, List.of());
    }
}
