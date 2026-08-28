package com.mindease.backend.coach.application;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;

import com.mindease.backend.coach.domain.CoachMemory;
import com.mindease.backend.coach.domain.CoachMemoryRepository;
import com.mindease.backend.coach.domain.Message;
import com.mindease.backend.coach.domain.MessageRepository;
import com.mindease.backend.coach.dto.CoachContext;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

/**
 * Builds a controlled, bounded context for the AI prompt.
 * Never sends entire databases to Gemini. Each context item is filtered
 * by relevance, freshness, sensitivity, and size limits.
 */
@Component
public class ContextBuilder {

    private static final Logger log = LoggerFactory.getLogger(ContextBuilder.class);

    private static final int MAX_RECENT_MESSAGES = 20;
    private static final int MAX_MEMORY_ITEMS = 10;
    private static final int MAX_RECENT_MOODS = 7;
    private static final int MAX_RECENT_JOURNALS = 3;
    private static final int MAX_CONTEXT_CHARS = 4000;

    private final MessageRepository messageRepo;
    private final CoachMemoryRepository memoryRepo;
    private final MoodEntryRepository moodRepo;
    private final JournalEntryRepository journalRepo;
    private final WellnessProfileRepository wellnessRepo;
    private final PersonalizationService personalizationService;

    public ContextBuilder(
            MessageRepository messageRepo,
            CoachMemoryRepository memoryRepo,
            MoodEntryRepository moodRepo,
            JournalEntryRepository journalRepo,
            WellnessProfileRepository wellnessRepo,
            PersonalizationService personalizationService) {
        this.messageRepo = messageRepo;
        this.memoryRepo = memoryRepo;
        this.moodRepo = moodRepo;
        this.journalRepo = journalRepo;
        this.wellnessRepo = wellnessRepo;
        this.personalizationService = personalizationService;
    }

    /**
     * Build the full context for a coach request.
     * Each context component is individually bounded and filtered.
     */
    public CoachContext buildContext(
            String userId,
            String conversationId,
            String currentMessage) {

        CoachContext ctx = new CoachContext();
        ctx.setCurrentMessage(currentMessage);

        // 1. Recent conversation history (bounded)
        ctx.setRecentConversation(buildConversationContext(userId, conversationId));

        // 2. Memory context
        ctx.setMemoryContext(buildMemoryContext(userId));

        // 3. Mood context (only recent, relevant data)
        ctx.setRelevantMoodContext(buildMoodContext(userId));

        // 4. Journal context (only metadata and high-level insights)
        ctx.setRelevantJournalContext(buildJournalContext(userId));

        // 5. Wellness profile context
        ctx.setWellnessContext(buildWellnessContext(userId));

        // 6. Unified personalized context (cross-feature signals)
        enrichWithPersonalizedContext(ctx, userId);

        // 7. RAG knowledge (will be retrieved separately by the coach service)
        // Set by CoachService after RAG retrieval

        // 8. Context metadata
        Map<String, String> metadata = new HashMap<>();
        metadata.put("contextVersion", "coach-ctx-v1");
        metadata.put("conversationMessageCount",
                String.valueOf(messageRepo.countByConversationIdAndUserId(conversationId, userId)));
        metadata.put("memoryCount",
                String.valueOf(memoryRepo.findByUserIdOrderByConfidenceDesc(userId).size()));
        metadata.put("builtAt", Instant.now().toString());
        ctx.setContextMetadata(metadata);

        return ctx;
    }

    private List<Map<String, String>> buildConversationContext(String userId, String conversationId) {
        List<Message> recent = messageRepo.findRecentMessages(conversationId, userId, MAX_RECENT_MESSAGES);
        return recent.stream()
                .filter(m -> m.getContent() != null && !m.getContent().isBlank())
                .map(m -> {
                    Map<String, String> entry = new HashMap<>();
                    entry.put("role", m.getRole());
                    entry.put("content", truncate(m.getContent(), 1000));
                    return entry;
                })
                .collect(Collectors.toList());
    }

    private String buildMemoryContext(String userId) {
        List<CoachMemory> memories = memoryRepo.findByUserIdOrderByConfidenceDesc(userId);
        if (memories.isEmpty()) return null;

        return memories.stream()
                .limit(MAX_MEMORY_ITEMS)
                .filter(m -> m.getContent() != null && !m.getContent().isBlank())
                .map(m -> m.getCategory() + ": " + m.getContent())
                .collect(Collectors.joining("\n"));
    }

    private String buildMoodContext(String userId) {
        try {
            List<MoodEntry> recentMoods = moodRepo.findByUserIdOrderByRecordedAtDesc(
                    userId, PageRequest.of(0, MAX_RECENT_MOODS));
            if (recentMoods.isEmpty()) return null;

            StringBuilder sb = new StringBuilder("Recent mood check-ins:\n");
            for (MoodEntry mood : recentMoods) {
                sb.append("- ").append(mood.getMood());
                if (mood.getEmotion() != null) sb.append(" (emotion: ").append(mood.getEmotion()).append(")");
                if (mood.getNote() != null && !mood.getNote().isBlank()) {
                    sb.append(" - note: ").append(truncate(mood.getNote(), 100));
                }
                sb.append("\n");
            }
            return truncate(sb.toString(), MAX_CONTEXT_CHARS / 4);
        } catch (Exception e) {
            log.debug("Could not build mood context: {}", e.getMessage());
            return null;
        }
    }

    private String buildJournalContext(String userId) {
        try {
            List<JournalEntry> recentJournals = journalRepo.findByUserIdOrderByCreatedAtDesc(
                    userId, PageRequest.of(0, MAX_RECENT_JOURNALS));
            if (recentJournals.isEmpty()) return null;

            StringBuilder sb = new StringBuilder("Recent journal activity:\n");
            for (JournalEntry journal : recentJournals) {
                sb.append("- \"").append(truncate(journal.getTitle(), 100)).append("\"");
                if (journal.getEmotion() != null) sb.append(" (emotion: ").append(journal.getEmotion()).append(")");
                if (journal.getAiAnalysis() != null && journal.getAiAnalysis().getEmotion() != null) {
                    sb.append(" [AI: ").append(journal.getAiAnalysis().getEmotion()).append("]");
                }
                sb.append("\n");
            }
            return truncate(sb.toString(), MAX_CONTEXT_CHARS / 4);
        } catch (Exception e) {
            log.debug("Could not build journal context: {}", e.getMessage());
            return null;
        }
    }

    private String buildWellnessContext(String userId) {
        try {
            var profile = wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(userId);
            if (profile.isEmpty()) return null;

            WellnessProfile wp = profile.get();
            StringBuilder sb = new StringBuilder("Wellness profile:\n");
            if (wp.getStressLevel() != null) sb.append("- Stress level: ").append(wp.getStressLevel()).append("\n");
            if (wp.getSleepQuality() != null) sb.append("- Sleep quality: ").append(wp.getSleepQuality()).append("\n");
            if (wp.getPrimaryFocus() != null) sb.append("- Primary focus: ").append(wp.getPrimaryFocus()).append("\n");
            if (wp.getLifestyleScore() != null) sb.append("- Lifestyle score: ").append(wp.getLifestyleScore()).append("/100\n");

            return truncate(sb.toString(), MAX_CONTEXT_CHARS / 4);
        } catch (Exception e) {
            log.debug("Could not build wellness context: {}", e.getMessage());
            return null;
        }
    }

    /**
     * Enrich coach context with cross-feature signals from the unified
     * personalized context. Adds recommendation feedback awareness
     * and overall user state without duplicating existing context.
     */
    private void enrichWithPersonalizedContext(CoachContext ctx, String userId) {
        try {
            PersonalizedContext pCtx = personalizationService.getContext(userId);
            if (pCtx == null) return;

            // Add recommendation interaction awareness
            StringBuilder sb = new StringBuilder();
            if (pCtx.getRecentlyCompletedRecommendations() != null
                    && !pCtx.getRecentlyCompletedRecommendations().isEmpty()) {
                sb.append("Recently completed activities: ")
                  .append(pCtx.getRecentlyCompletedRecommendations().size()).append("\n");
            }
            if (pCtx.getDominantMood() != null) {
                sb.append("Recent dominant mood: ").append(pCtx.getDominantMood()).append("\n");
            }
            if (pCtx.getMoodTrend() != null && !"unknown".equals(pCtx.getMoodTrend())) {
                sb.append("Mood trend: ").append(pCtx.getMoodTrend()).append("\n");
            }
            if (pCtx.getEmotionalThemes() != null && !pCtx.getEmotionalThemes().isEmpty()) {
                sb.append("Emotional themes: ")
                  .append(String.join(", ", pCtx.getEmotionalThemes().stream().limit(5).toList()))
                  .append("\n");
            }
            if (sb.length() > 0) {
                ctx.setSafetySignals(truncate(sb.toString(), 500));
            }

            // Add preference signals to user preferences map
            if (pCtx.getPreferenceSignals() != null && !pCtx.getPreferenceSignals().isEmpty()) {
                ctx.setUserPreferences(new HashMap<>(pCtx.getPreferenceSignals()));
            }
        } catch (Exception e) {
            // Personalization enrichment is best-effort
            log.debug("Could not enrich coach context with personalized context: {}", e.getMessage());
        }
    }

    private static String truncate(String s, int max) {
        if (s == null) return null;
        return s.length() > max ? s.substring(0, max) + "…" : s;
    }
}
