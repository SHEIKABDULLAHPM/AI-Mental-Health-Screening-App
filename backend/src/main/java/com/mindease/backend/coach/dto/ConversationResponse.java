package com.mindease.backend.coach.dto;

import java.time.Instant;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.mindease.backend.coach.domain.Conversation;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ConversationResponse(
        String id,
        String title,
        String preview,
        int messageCount,
        String safetyState,
        Instant createdAt,
        Instant updatedAt
) {
    public static ConversationResponse from(Conversation c) {
        return new ConversationResponse(
                c.getId(),
                c.getTitle(),
                c.getLastMessagePreview(),
                c.getMessageCount(),
                c.getSafetyState(),
                c.getCreatedAt(),
                c.getUpdatedAt());
    }
}
