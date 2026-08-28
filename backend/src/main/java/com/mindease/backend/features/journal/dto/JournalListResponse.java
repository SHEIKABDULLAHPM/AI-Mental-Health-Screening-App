package com.mindease.backend.features.journal.dto;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonInclude;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record JournalListResponse(
        List<JournalResponse> entries,
        long total,
        int page,
        int size,
        boolean hasMore) {
}
