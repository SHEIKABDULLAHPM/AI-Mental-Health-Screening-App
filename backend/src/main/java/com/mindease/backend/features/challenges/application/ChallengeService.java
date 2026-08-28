package com.mindease.backend.features.challenges.application;

import java.time.Instant;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.ChallengeRepository;
import com.mindease.backend.features.challenges.domain.UserChallenge;
import com.mindease.backend.features.challenges.domain.UserChallengeRepository;
import com.mindease.backend.features.challenges.dto.ChallengeResponse;

@Service
public class ChallengeService {

    private final ChallengeRepository challengeRepository;
    private final UserChallengeRepository userChallengeRepository;

    public ChallengeService(ChallengeRepository challengeRepository,
                            UserChallengeRepository userChallengeRepository) {
        this.challengeRepository = challengeRepository;
        this.userChallengeRepository = userChallengeRepository;
    }

    public List<ChallengeResponse> getAvailableChallenges() {
        return challengeRepository.findByActiveTrue().stream()
                .map(c -> ChallengeResponse.from(c, null))
                .collect(Collectors.toList());
    }

    public ChallengeResponse getChallengeById(String userId, String challengeId) {
        Challenge challenge = challengeRepository.findByIdAndActiveTrue(challengeId)
                .orElseThrow(() -> ApiException.notFound("Challenge not found or no longer available."));

        UserChallenge userChallenge = userChallengeRepository
                .findByUserIdAndChallengeId(userId, challengeId)
                .orElse(null);

        return ChallengeResponse.from(challenge, userChallenge);
    }

    public ChallengeResponse startChallenge(String userId, String challengeId) {
        Challenge challenge = challengeRepository.findByIdAndActiveTrue(challengeId)
                .orElseThrow(() -> ApiException.notFound("Challenge not found or no longer available."));

        userChallengeRepository.findByUserIdAndChallengeId(userId, challengeId)
                .ifPresent(uc -> {
                    throw ApiException.badRequest("You have already started this challenge.");
                });

        Instant now = Instant.now();
        UserChallenge userChallenge = new UserChallenge();
        userChallenge.setUserId(userId);
        userChallenge.setChallengeId(challengeId);
        userChallenge.setCurrentDay(0);
        userChallenge.setCompleted(false);
        userChallenge.setStartedAt(now);
        userChallenge.setUpdatedAt(now);

        userChallengeRepository.save(userChallenge);
        return ChallengeResponse.from(challenge, userChallenge);
    }

    public ChallengeResponse updateProgress(String userId, String challengeId) {
        UserChallenge userChallenge = userChallengeRepository.findByUserIdAndChallengeId(userId, challengeId)
                .orElseThrow(() -> ApiException.notFound("User challenge not found or no longer available."));

        if (userChallenge.isCompleted()) {
            throw ApiException.badRequest("This challenge is already completed.");
        }

        Challenge challenge = challengeRepository.findById(userChallenge.getChallengeId())
                .orElseThrow(() -> ApiException.notFound("Challenge not found."));

        userChallenge.setCurrentDay(userChallenge.getCurrentDay() + 1);

        if (userChallenge.getCurrentDay() >= challenge.getDurationDays()) {
            userChallenge.setCompleted(true);
            userChallenge.setCompletedAt(Instant.now());
        }

        userChallenge.setUpdatedAt(Instant.now());
        userChallengeRepository.save(userChallenge);

        return ChallengeResponse.from(challenge, userChallenge);
    }

    public ChallengeResponse completeChallenge(String userId, String challengeId) {
        UserChallenge userChallenge = userChallengeRepository.findByUserIdAndChallengeId(userId, challengeId)
                .orElseThrow(() -> ApiException.notFound("User challenge not found or no longer available."));

        if (userChallenge.isCompleted()) {
            throw ApiException.badRequest("This challenge is already completed.");
        }

        Challenge challenge = challengeRepository.findById(userChallenge.getChallengeId())
                .orElseThrow(() -> ApiException.notFound("Challenge not found."));

        userChallenge.setCompleted(true);
        userChallenge.setCompletedAt(Instant.now());
        userChallenge.setCurrentDay(challenge.getDurationDays());
        userChallenge.setUpdatedAt(Instant.now());
        userChallengeRepository.save(userChallenge);

        return ChallengeResponse.from(challenge, userChallenge);
    }

    public List<ChallengeResponse> getActiveChallenges(String userId) {
        List<UserChallenge> active = userChallengeRepository
                .findByUserIdAndCompletedFalseOrderByStartedAtDesc(userId);

        return active.stream()
                .map(uc -> {
                    Challenge challenge = challengeRepository.findById(uc.getChallengeId())
                            .orElse(null);
                    return challenge != null ? ChallengeResponse.from(challenge, uc) : null;
                })
                .filter(r -> r != null)
                .collect(Collectors.toList());
    }

    public List<ChallengeResponse> getCompletedChallenges(String userId) {
        List<UserChallenge> completed = userChallengeRepository
                .findByUserIdAndCompletedTrueOrderByCompletedAtDesc(userId);

        return completed.stream()
                .map(uc -> {
                    Challenge challenge = challengeRepository.findById(uc.getChallengeId())
                            .orElse(null);
                    return challenge != null ? ChallengeResponse.from(challenge, uc) : null;
                })
                .filter(r -> r != null)
                .collect(Collectors.toList());
    }
}
