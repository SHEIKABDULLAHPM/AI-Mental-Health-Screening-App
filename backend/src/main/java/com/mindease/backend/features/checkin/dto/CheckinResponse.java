package com.mindease.backend.features.checkin.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

import com.mindease.backend.features.checkin.domain.DailyCheckin;

public record CheckinResponse(
        String id,
        LocalDate date,
        Integer mood,
        Integer sleep,
        Integer energy,
        Integer stress,
        List<String> activities,
        Instant createdAt,
        Instant updatedAt) {

    public static CheckinResponse from(DailyCheckin entity) {
        return new CheckinResponse(
                entity.getId(),
                entity.getDate(),
                entity.getMood(),
                entity.getSleep(),
                entity.getEnergy(),
                entity.getStress(),
                entity.getActivities(),
                entity.getCreatedAt(),
                entity.getUpdatedAt());
    }
}
