package com.mindease.backend.features.physical.dto;

import java.time.Instant;
import java.util.List;

import com.mindease.backend.features.physical.domain.SyncStatus;

/**
 * Outcome of a synchronization batch. Records that fail validation are
 * rejected with a reason instead of being silently accepted; duplicates are
 * reported separately because they indicate a replay, not corruption.
 */
public record SyncResponse(
        String syncSessionId,
        SyncStatus status,
        int received,
        int accepted,
        int duplicates,
        int rejected,
        List<Rejection> rejections,
        Instant completedAt) {

    public record Rejection(String category, int index, String reason) {
    }
}
