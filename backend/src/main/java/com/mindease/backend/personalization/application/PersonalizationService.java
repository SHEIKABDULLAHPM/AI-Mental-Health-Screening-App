package com.mindease.backend.personalization.application;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.personalization.domain.PersonalizedContextRepository;
import com.mindease.backend.personalization.domain.PersonalizationFeedback;
import com.mindease.backend.personalization.domain.PersonalizationFeedbackRepository;

/**
 * Service for managing the centralized personalized context.
 *
 * <p>Provides cached context retrieval with graceful degradation,
 * feedback recording for the cross-feature feedback loop,
 * and context refresh operations.</p>
 */
@Service
public class PersonalizationService {

    private static final Logger log = LoggerFactory.getLogger(PersonalizationService.class);

    /** How far back to look for feedback signals. */
    private static final int FEEDBACK_WINDOW_DAYS = 14;

    private final PersonalizedContextRepository contextRepo;
    private final PersonalizationFeedbackRepository feedbackRepo;
    private final PersonalizationContextBuilder contextBuilder;

    public PersonalizationService(
            PersonalizedContextRepository contextRepo,
            PersonalizationFeedbackRepository feedbackRepo,
            PersonalizationContextBuilder contextBuilder) {
        this.contextRepo = contextRepo;
        this.feedbackRepo = feedbackRepo;
        this.contextBuilder = contextBuilder;
    }

    /**
     * Get the personalized context for a user.
     * Returns cached context if fresh; otherwise rebuilds.
     * Never throws — degrades gracefully to an empty context.
     */
    public PersonalizedContext getContext(String userId) {
        try {
            // Try cached context first
            Instant now = Instant.now();
            var cached = contextRepo.findFirstByUserIdAndExpiresAtAfterOrderByGeneratedAtDesc(
                    userId, now);
            if (cached.isPresent()) {
                return cached.get();
            }

            // Cache miss or expired — rebuild
            return refreshContext(userId);

        } catch (Exception e) {
            log.warn("Failed to get personalized context for user {}: {}", userId, e.getMessage());
            // Return a minimal empty context rather than failing
            return buildEmptyContext(userId);
        }
    }

    /**
     * Force a context refresh for a user.
     * Called when a significant feature event occurs (mood recorded, journal created, etc.)
     */
    public PersonalizedContext refreshContext(String userId) {
        try {
            PersonalizedContext fresh = contextBuilder.build(userId);
            PersonalizedContext saved = contextRepo.save(fresh);
            log.debug("Refreshed personalized context for user {}", userId);
            return saved;
        } catch (Exception e) {
            log.warn("Failed to refresh personalized context for user {}: {}", userId, e.getMessage());
            return buildEmptyContext(userId);
        }
    }

    /**
     * Record a cross-feature feedback event.
     * Used to build the feedback loop for future personalization.
     */
    public void recordFeedback(String userId, String eventType, String contentId,
                                 String sourceFeature, java.util.Map<String, String> metadata) {
        try {
            PersonalizationFeedback feedback = new PersonalizationFeedback();
            feedback.setUserId(userId);
            feedback.setEventType(eventType);
            feedback.setContentId(contentId);
            feedback.setSourceFeature(sourceFeature);
            feedback.setMetadata(metadata);
            feedback.setWeight(calculateFeedbackWeight(eventType));
            feedback.setCreatedAt(Instant.now());
            feedbackRepo.save(feedback);

            // Trigger a context refresh if this is a significant event
            if (isSignificantEvent(eventType)) {
                refreshContext(userId);
            }
        } catch (Exception e) {
            log.warn("Failed to record personalization feedback for user {}: {}",
                    userId, e.getMessage());
        }
    }

    /**
     * Get recent feedback events for a user.
     */
    public List<PersonalizationFeedback> getRecentFeedback(String userId) {
        try {
            Instant since = Instant.now().minus(FEEDBACK_WINDOW_DAYS, ChronoUnit.DAYS);
            return feedbackRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(userId, since);
        } catch (Exception e) {
            log.debug("Failed to get recent feedback for user {}: {}", userId, e.getMessage());
            return List.of();
        }
    }

    /**
     * Check if a recommendation was recently dismissed or marked as not useful.
     * Used by the recommendation engine to avoid repeating unwanted content.
     */
    public boolean isRecommendationAvoided(String userId, String contentId) {
        try {
            List<PersonalizationFeedback> feedback =
                    feedbackRepo.findByUserIdAndContentIdOrderByCreatedAtDesc(userId, contentId);
            return feedback.stream().anyMatch(f ->
                    "RECOMMENDATION_DISMISSED".equals(f.getEventType()) ||
                    "RECOMMENDATION_NOT_USEFUL".equals(f.getEventType()));
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Check if a recommendation was recently completed.
     */
    public boolean isRecommendationCompleted(String userId, String contentId) {
        try {
            Instant since = Instant.now().minus(FEEDBACK_WINDOW_DAYS, ChronoUnit.DAYS);
            long count = feedbackRepo.countByUserIdAndEventTypeAndCreatedAtAfter(
                    userId, "RECOMMENDATION_COMPLETED", since);
            return count > 0;
        } catch (Exception e) {
            return false;
        }
    }

    // ── Private helpers ───────────────────────────────────────────

    private PersonalizedContext buildEmptyContext(String userId) {
        PersonalizedContext empty = new PersonalizedContext();
        empty.setUserId(userId);
        empty.setContextVersion("personalization-ctx-v1");
        empty.setGeneratedAt(Instant.now());
        empty.setExpiresAt(Instant.now().plus(5, ChronoUnit.MINUTES));
        empty.setPersonalizationSummary("Personalization is being set up. Start tracking your mood to unlock personalized insights.");
        return empty;
    }

    private double calculateFeedbackWeight(String eventType) {
        return switch (eventType) {
            case "RECOMMENDATION_COMPLETED" -> 1.0;
            case "RECOMMENDATION_HELPFUL" -> 0.9;
            case "RECOMMENDATION_NOT_USEFUL" -> 0.7;
            case "RECOMMENDATION_DISMISSED" -> 0.6;
            case "ACTIVITY_COMPLETED" -> 0.8;
            case "MOOD_RECORDED" -> 0.5;
            case "JOURNAL_CREATED" -> 0.5;
            case "COACH_INTERACTION" -> 0.4;
            case "PREFERENCE_EXPRESSED" -> 0.8;
            default -> 0.5;
        };
    }

    private boolean isSignificantEvent(String eventType) {
        return "RECOMMENDATION_COMPLETED".equals(eventType) ||
               "RECOMMENDATION_DISMISSED".equals(eventType) ||
               "RECOMMENDATION_NOT_USEFUL".equals(eventType) ||
               "RECOMMENDATION_HELPFUL".equals(eventType) ||
               "MOOD_RECORDED".equals(eventType) ||
               "JOURNAL_CREATED".equals(eventType) ||
               "PREFERENCE_EXPRESSED".equals(eventType);
    }
}
