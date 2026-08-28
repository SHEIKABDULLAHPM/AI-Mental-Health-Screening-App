package com.mindease.backend.features.challenges.dto;

import java.time.Instant;

import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.UserChallenge;

public record ChallengeResponse(
        String id,
        String title,
        String description,
        int durationDays,
        int points,
        String type,
        int currentDay,
        boolean isCompleted) {

    public static ChallengeResponse from(Challenge challenge, UserChallenge userChallenge) {
        if (userChallenge == null) {
            return new ChallengeResponse(
                    challenge.getId(),
                    challenge.getTitle(),
                    challenge.getDescription(),
                    challenge.getDurationDays(),
                    challenge.getPoints(),
                    challenge.getType(),
                    0,
                    false);
        }
        return new ChallengeResponse(
                challenge.getId(),
                challenge.getTitle(),
                challenge.getDescription(),
                challenge.getDurationDays(),
                challenge.getPoints(),
                challenge.getType(),
                userChallenge.getCurrentDay(),
                userChallenge.isCompleted());
    }
}
