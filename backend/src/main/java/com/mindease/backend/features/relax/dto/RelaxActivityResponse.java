package com.mindease.backend.features.relax.dto;

import com.mindease.backend.features.relax.domain.RelaxActivity;

public record RelaxActivityResponse(
        String id,
        String title,
        String description,
        String category,
        int durationMinutes,
        Integer iconCodePoint,
        boolean completedByUser) {

    public static RelaxActivityResponse from(RelaxActivity entity, boolean completedByUser) {
        return new RelaxActivityResponse(
                entity.getId(),
                entity.getTitle(),
                entity.getDescription(),
                entity.getCategory(),
                entity.getDurationMinutes(),
                entity.getIconCodePoint(),
                completedByUser);
    }
}
