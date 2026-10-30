package com.mindease.backend.features.challenges.application;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.mindease.backend.features.challenges.domain.ChallengeType;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Facade used by other feature services (Mood, Journal, Relax, Recommendations)
 * to report that a real, persisted activity has occurred. Keeps the challenge
 * module decoupled from the originating features while remaining the single
 * integration point.
 *
 * <p>When callers pass {@code null} for {@code userZone}, the timezone is
 * resolved from the {@code X-User-Timezone} request header via
 * {@link UserTimeZoneHolder}. Falls back to UTC when neither is available.</p>
 */
@Service
public class ChallengeActivityService {

    private static final Logger log = LoggerFactory.getLogger(ChallengeActivityService.class);

    private final ChallengeService challengeService;

    public ChallengeActivityService(ChallengeService challengeService) {
        this.challengeService = challengeService;
    }

    public void onMoodRecorded(String userId, String moodEntryId, String userZone) {
        challengeService.applyActivity(userId, ChallengeType.MOOD_CHECK_IN, moodEntryId,
                resolveZone(userZone));
    }

    public void onJournalCreated(String userId, String journalEntryId, String userZone) {
        challengeService.applyActivity(userId, ChallengeType.JOURNALING, journalEntryId,
                resolveZone(userZone));
    }

    public void onRelaxCompleted(String userId, String relaxCompletionId, String userZone) {
        challengeService.applyActivity(userId, ChallengeType.RELAXATION, relaxCompletionId,
                resolveZone(userZone));
    }

    public void onRecommendationCompleted(String userId, String contentId, String userZone) {
        challengeService.applyActivity(userId, ChallengeType.HEALTHY_ROUTINE, contentId,
                resolveZone(userZone));
    }

    public void onGameCompleted(String userId, String gameResultId, String userZone) {
        challengeService.applyActivity(userId, ChallengeType.GAME_ACTIVITY, gameResultId,
                resolveZone(userZone));
    }

    /**
     * Resolve the effective timezone: explicit param > request header > null (UTC default).
     */
    private static String resolveZone(String explicit) {
        if (explicit != null && !explicit.isBlank()) {
            return explicit;
        }
        return UserTimeZoneHolder.get();
    }
}
