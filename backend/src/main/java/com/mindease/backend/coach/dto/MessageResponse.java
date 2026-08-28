package com.mindease.backend.coach.dto;

import java.time.Instant;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.mindease.backend.coach.domain.Message;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record MessageResponse(
        String id,
        String conversationId,
        String role,
        String content,
        String status,
        int sequence,
        String safetyState,
        String suggestions,
        String clientMessageId,
        Instant createdAt,
        Instant completedAt
) {
    public static MessageResponse from(Message m) {
        return new MessageResponse(
                m.getId(),
                m.getConversationId(),
                m.getRole(),
                m.getContent(),
                m.getStatus(),
                m.getSequence(),
                m.getSafetyState(),
                m.getSuggestions(),
                m.getClientMessageId(),
                m.getCreatedAt(),
                m.getCompletedAt());
    }
}
