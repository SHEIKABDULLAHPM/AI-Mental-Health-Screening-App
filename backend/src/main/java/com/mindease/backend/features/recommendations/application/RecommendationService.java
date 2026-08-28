package com.mindease.backend.features.recommendations.application;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.recommendations.domain.RecommendationContent;
import com.mindease.backend.features.recommendations.domain.RecommendationContentRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteraction;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.features.recommendations.dto.FeedbackRequest;
import com.mindease.backend.features.recommendations.dto.InteractionRequest;
import com.mindease.backend.features.recommendations.dto.RecommendationResponse;

/**
 * Full personalization pipeline:
 * Context → Safety → Candidates → Rank → Diversify → Validate → Response
 */
@Service
public class RecommendationService {

    private static final Logger log = LoggerFactory.getLogger(RecommendationService.class);
    private static final int MAX_RECOMMENDATIONS = 10;
    private static final int DIVERSITY_WINDOW = 3;

    private final RecommendationContentRepository contentRepo;
    private final RecommendationInteractionRepository interactionRepo;
    private final RecommendationContextBuilder contextBuilder;
    private final RecommendationRankingService rankingService;
    private final PersonalizationService personalizationService;

    public RecommendationService(
            RecommendationContentRepository contentRepo,
            RecommendationInteractionRepository interactionRepo,
            RecommendationContextBuilder contextBuilder,
            RecommendationRankingService rankingService,
            PersonalizationService personalizationService) {
        this.contentRepo = contentRepo;
        this.interactionRepo = interactionRepo;
        this.contextBuilder = contextBuilder;
        this.rankingService = rankingService;
        this.personalizationService = personalizationService;
    }

    /**
     * Get personalized recommendations for a user.
     * @param category optional category filter
     */
    public List<RecommendationResponse> getRecommendations(String userId, String category) {
        // 1. Build context
        Map<String, Object> context = contextBuilder.buildContext(userId);

        // 2. Get eligible candidates (active content, optionally filtered by category)
        List<RecommendationContent> candidates;
        if (category != null && !category.isBlank()) {
            candidates = contentRepo.findByActiveTrueAndCategory(category);
        } else {
            candidates = contentRepo.findByActiveTrue();
        }

        if (candidates.isEmpty()) {
            log.warn("No active recommendation content available");
            return List.of();
        }

        // 3. Safety filter: remove content with safety tags
        candidates = applySafetyFilter(candidates);

        // 4. Rank candidates
        List<RecommendationRankingService.ScoredRecommendation> scored =
                rankingService.rank(candidates, context);

        // 5. Diversify: ensure category variety
        scored = applyDiversity(scored);

        // 6. Take top N
        scored = scored.stream()
                .limit(MAX_RECOMMENDATIONS)
                .collect(Collectors.toList());

        // 7. Convert to response DTOs
        Instant now = Instant.now();
        return scored.stream()
                .map(s -> new RecommendationResponse(
                        s.content().getId(),
                        s.content().getTitle(),
                        s.content().getDescription(),
                        s.content().getCategory(),
                        s.content().getType(),
                        s.reason(),
                        s.content().getDuration(),
                        s.content().getDifficulty(),
                        s.content().getContentReference(),
                        s.content().getContentVersion(),
                        now))
                .toList();
    }

    /**
     * Get a single recommendation by ID with a dynamic reason.
     * Uses the same ranking logic to generate a personalized explanation.
     */
    public RecommendationResponse getRecommendationById(String userId, String id) {
        RecommendationContent content = contentRepo.findByIdAndActiveTrue(id)
                .orElseThrow(() -> ApiException.notFound(
                        "Recommendation not found or no longer available."));

        // Generate a dynamic reason using the ranking engine
        Map<String, Object> context = contextBuilder.buildContext(userId);
        List<RecommendationRankingService.ScoredRecommendation> scored =
                rankingService.rank(List.of(content), context);
        String reason = scored.isEmpty()
                ? "A wellness activity you can try right now."
                : scored.get(0).reason();

        return new RecommendationResponse(
                content.getId(),
                content.getTitle(),
                content.getDescription(),
                content.getCategory(),
                content.getType(),
                reason,
                content.getDuration(),
                content.getDifficulty(),
                content.getContentReference(),
                content.getContentVersion(),
                Instant.now());
    }

    /**
     * Record user feedback on a recommendation.
     */
    public void recordFeedback(String userId, String contentId, FeedbackRequest request) {
        // Validate feedback type
        String type = request.feedbackType().toUpperCase();
        if (!List.of("HELPFUL", "NOT_USEFUL", "ALREADY_COMPLETED", "DISMISSED").contains(type)) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Invalid feedback type. Must be: HELPFUL, NOT_USEFUL, ALREADY_COMPLETED, DISMISSED");
        }

        // Verify content exists
        contentRepo.findByIdAndActiveTrue(contentId)
                .orElseThrow(() -> ApiException.notFound("Recommendation not found."));

        // Idempotency check
        if (request.requestId() != null) {
            var existing = interactionRepo.findByUserIdAndRequestId(userId, request.requestId());
            if (existing.isPresent()) return;
        }

        saveInteraction(userId, contentId, type, request.requestId());

        // Record in personalization feedback loop (fire-and-forget)
        String eventType = mapFeedbackToPersonalizationEvent(type);
        personalizationService.recordFeedback(userId, eventType, contentId,
                "recommendations", java.util.Map.of("feedbackType", type));
    }

    /**
     * Record user interaction (shown, opened, started, completed).
     */
    public void recordInteraction(String userId, String contentId, InteractionRequest request) {
        String type = request.interactionType().toUpperCase();
        if (!List.of("SHOWN", "OPENED", "STARTED", "COMPLETED").contains(type)) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Invalid interaction type. Must be: SHOWN, OPENED, STARTED, COMPLETED");
        }

        contentRepo.findByIdAndActiveTrue(contentId)
                .orElseThrow(() -> ApiException.notFound("Recommendation not found."));

        // Idempotency check
        if (request.requestId() != null) {
            var existing = interactionRepo.findByUserIdAndRequestId(userId, request.requestId());
            if (existing.isPresent()) return;
        }

        saveInteraction(userId, contentId, type, request.requestId());

        // Record in personalization feedback loop (fire-and-forget)
        String eventType = mapInteractionToPersonalizationEvent(type);
        personalizationService.recordFeedback(userId, eventType, contentId,
                "recommendations", java.util.Map.of("interactionType", type));
    }

    // ── Seeding ──

    /**
     * Seed initial recommendation content if none exists.
     * Called by RecommendationSeeder on application startup.
     */
    public void seedRecommendations() {
        if (contentRepo.countByActiveTrue() > 0) {
            log.debug("Recommendation content already seeded, skipping");
            return;
        }

        List<RecommendationContent> seeds = List.of(
                createSeedContent("5-Minute Reset", "A quick mindfulness exercise to help you reset and refocus during a busy day.",
                        "exercises", "guided", "5 min", "easy", "/activities/breathing-reset",
                        List.of("stress", "anxiety", "quick"), List.of("stressed", "anxious", "overwhelmed")),
                createSeedContent("Deep Breathing Technique", "A guided 4-7-8 breathing exercise to calm your nervous system.",
                        "meditation", "guided", "10 min", "easy", "/activities/breathing-deep",
                        List.of("anxiety", "calm", "sleep"), List.of("anxious", "stressed")),
                createSeedContent("Progressive Muscle Relaxation", "Release tension step by step through guided muscle relaxation.",
                        "exercises", "exercise", "15 min", "medium", "/activities/pmr",
                        List.of("stress", "tension", "relaxation"), List.of("tired", "stressed")),
                createSeedContent("Gratitude Journaling Prompt", "Reflect on three things you're grateful for today.",
                        "articles", "article", "10 min", "easy", "/activities/gratitude",
                        List.of("mood", "gratitude", "reflection"), List.of("sad", "low")),
                createSeedContent("Sleep Soundscape", "Ambient sounds designed to help you fall asleep peacefully.",
                        "sounds", "ambient", "60 min", "easy", "/activities/sleep-sounds",
                        List.of("sleep", "calm", "ambient"), List.of("tired", "restless")),
                createSeedContent("Morning Energy Boost", "Start your day with a gentle stretching and breathing routine.",
                        "exercises", "exercise", "10 min", "easy", "/activities/morning-energy",
                        List.of("energy", "morning", "mood"), List.of("tired", "neutral")),
                createSeedContent("Body Scan Meditation", "A 10-minute guided body scan to release physical tension.",
                        "meditation", "guided", "10 min", "medium", "/activities/body-scan",
                        List.of("relaxation", "tension", "meditation"), List.of("stressed", "anxious")),
                createSeedContent("Mindful Walking Guide", "A guided mindful walking exercise to ground yourself.",
                        "exercises", "exercise", "15 min", "easy", "/activities/mindful-walking",
                        List.of("grounding", "calm", "movement"), List.of("anxious", "restless")),
                createSeedContent("Mood Check-in Reminder", "Take a moment to check in with how you're feeling right now.",
                        "personalized", "routine", "2 min", "easy", "/mood-checkin",
                        List.of("mood", "awareness", "check-in"), List.of("neutral")),
                createSeedContent("Sleep Hygiene Tips", "Evidence-based tips for improving your sleep quality.",
                        "articles", "article", "5 min", "easy", "/activities/sleep-tips",
                        List.of("sleep", "hygiene", "wellness"), List.of("tired"))
        );

        contentRepo.saveAll(seeds);
        log.info("Seeded {} recommendation content items", seeds.size());
    }

    private RecommendationContent createSeedContent(String title, String description,
            String category, String type, String duration, String difficulty,
            String contentReference, List<String> tags, List<String> eligibilityTags) {
        RecommendationContent c = new RecommendationContent();
        c.setTitle(title);
        c.setDescription(description);
        c.setCategory(category);
        c.setType(type);
        c.setDuration(duration);
        c.setDifficulty(difficulty);
        c.setContentReference(contentReference);
        c.setTags(tags);
        c.setEligibilityTags(eligibilityTags);
        c.setSafetyTags(List.of());
        c.setActive(true);
        c.setContentVersion(1);
        c.setCreatedAt(Instant.now());
        c.setUpdatedAt(Instant.now());
        return c;
    }

    // ── Private helpers ──

    private List<RecommendationContent> applySafetyFilter(List<RecommendationContent> candidates) {
        return candidates.stream()
                .filter(c -> {
                    if (c.getSafetyTags() == null) return true;
                    // Remove content with unsafe safety tags
                    return !c.getSafetyTags().contains("crisis") &&
                           !c.getSafetyTags().contains("clinical") &&
                           !c.getSafetyTags().contains("medication");
                })
                .collect(Collectors.toList());
    }

    private List<RecommendationRankingService.ScoredRecommendation> applyDiversity(
            List<RecommendationRankingService.ScoredRecommendation> scored) {
        // Ensure no more than 2 consecutive items from the same category
        List<RecommendationRankingService.ScoredRecommendation> result = new ArrayList<>();
        String lastCategory = null;
        int consecutiveCount = 0;

        for (RecommendationRankingService.ScoredRecommendation item : scored) {
            String category = item.content().getCategory();
            if (category.equals(lastCategory)) {
                consecutiveCount++;
                if (consecutiveCount >= DIVERSITY_WINDOW) {
                    continue; // Skip to maintain diversity
                }
            } else {
                lastCategory = category;
                consecutiveCount = 1;
            }
            result.add(item);
        }

        return result;
    }

    private void saveInteraction(String userId, String contentId,
            String interactionType, String requestId) {
        RecommendationInteraction interaction = new RecommendationInteraction();
        interaction.setUserId(userId);
        interaction.setContentId(contentId);
        interaction.setInteractionType(interactionType);
        interaction.setRequestId(requestId);
        interaction.setCreatedAt(Instant.now());
        interactionRepo.save(interaction);
    }

    private String mapFeedbackToPersonalizationEvent(String feedbackType) {
        return switch (feedbackType) {
            case "HELPFUL" -> "RECOMMENDATION_HELPFUL";
            case "NOT_USEFUL" -> "RECOMMENDATION_NOT_USEFUL";
            case "ALREADY_COMPLETED" -> "RECOMMENDATION_COMPLETED";
            case "DISMISSED" -> "RECOMMENDATION_DISMISSED";
            default -> "RECOMMENDATION_FEEDBACK";
        };
    }

    private String mapInteractionToPersonalizationEvent(String interactionType) {
        return switch (interactionType) {
            case "COMPLETED" -> "ACTIVITY_COMPLETED";
            case "STARTED" -> "ACTIVITY_STARTED";
            default -> "ACTIVITY_INTERACTION";
        };
    }
}
