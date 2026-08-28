package com.mindease.backend.coach.dto;

import jakarta.validation.constraints.Size;

public record CreateConversationRequest(
        @Size(max = 200) String title
) {
}
