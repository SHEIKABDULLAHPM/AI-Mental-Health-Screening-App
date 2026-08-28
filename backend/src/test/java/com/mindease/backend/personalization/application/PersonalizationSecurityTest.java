package com.mindease.backend.personalization.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageRequest;

import com.mindease.backend.coach.domain.CoachMemory;
import com.mindease.backend.coach.domain.CoachMemoryRepository;
import com.mindease.backend.coach.domain.ConversationRepository;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.mood.application.MoodTrendAnalyzer;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

/**
 * Explicitly tests that User A's personalization context never
 * contains data derived from User B's activity.
 *
 * <p>Tests the IDOR protection: the PersonalizationContextBuilder
 * always receives the authenticated user's ID and never crosses
 * user boundaries.</p>
 */
@ExtendWith(MockitoExtension.class)
class PersonalizationSecurityTest {

    @Mock private MoodEntryRepository moodRepo;
    @Mock private JournalEntryRepository journalRepo;
    @Mock private RecommendationInteractionRepository interactionRepo;
    @Mock private ConversationRepository conversationRepo;
    @Mock private CoachMemoryRepository memoryRepo;
    @Mock private WellnessProfileRepository wellnessRepo;
    @Mock private MoodTrendAnalyzer moodTrendAnalyzer;

    private PersonalizationContextBuilder builder;

    private static final String USER_A = "user-a-123";
    private static final String USER_B = "user-b-456";

    @BeforeEach
    void setUp() {
        builder = new PersonalizationContextBuilder(
                moodRepo, journalRepo, interactionRepo, conversationRepo,
                memoryRepo, wellnessRepo, moodTrendAnalyzer);
    }

    @Test
    void userA_context_neverContainsUserBMoodData() {
        // User A has no moods
        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        // User B has moods (should NOT appear in User A's context)
        MoodEntry userBMood = new MoodEntry();
        userBMood.setUserId(USER_B);
        userBMood.setMood("happy");
        userBMood.setEmotion("joy");
        userBMood.setRecordedAt(Instant.now());
        // The repo should never be called with USER_B when building USER_A's context
        // But if it were, we verify the result doesn't contain it

        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_A), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_A)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_A))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctxA = builder.build(USER_A);

        // Verify User A's context has no User B data
        assertThat(ctxA.getUserId()).isEqualTo(USER_A);
        assertThat(ctxA.getUserId()).isNotEqualTo(USER_B);
        assertThat(ctxA.getCurrentMood()).isNull();
        assertThat(ctxA.getCurrentEmotion()).isNull();
    }

    @Test
    void userA_context_neverContainsUserBJournalData() {
        // User A has no journals
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_A), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_A)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_A))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctxA = builder.build(USER_A);

        // User A's context should not have journal data from User B
        assertThat(ctxA.getUserId()).isEqualTo(USER_A);
        assertThat(ctxA.isJournalAvailable()).isFalse();
        assertThat(ctxA.getRecentJournalCount()).isEqualTo(0);
        assertThat(ctxA.getJournalEmotionalThemes()).isNull();
    }

    @Test
    void userA_context_neverContainsUserBCoachData() {
        // User A has no coach conversations
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_A)).thenReturn(List.of());

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_A), any())).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_A))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctxA = builder.build(USER_A);

        assertThat(ctxA.isCoachActive()).isFalse();
        assertThat(ctxA.getCoachMemoryCategories()).isEmpty();
        assertThat(ctxA.getCoachTopics()).isEmpty();
    }

    @Test
    void userA_context_withUserData_isIsolated() {
        // User A has their own mood data
        MoodEntry userAMood = new MoodEntry();
        userAMood.setUserId(USER_A);
        userAMood.setMood("stressed");
        userAMood.setEmotion("anxious");
        userAMood.setRecordedAt(Instant.now());

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of(userAMood));
        when(moodRepo.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(eq(USER_A), any()))
                .thenReturn(List.of(userAMood));
        when(moodTrendAnalyzer.analyzeTrend(any())).thenReturn(
                java.util.Map.of("direction", "stable", "description", "Consistent"));

        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_A), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_A), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_A)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_A))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctxA = builder.build(USER_A);

        // Should only contain User A's own data
        assertThat(ctxA.getUserId()).isEqualTo(USER_A);
        assertThat(ctxA.getCurrentMood()).isEqualTo("stressed");
        assertThat(ctxA.getCurrentEmotion()).isEqualTo("anxious");
        assertThat(ctxA.getDominantMood()).isEqualTo("stressed");

        // Now build User B's context — should be completely separate
        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_B), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_B), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_B), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_B), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_B)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_B))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctxB = builder.build(USER_B);

        // User B's context should NOT contain User A's mood data
        assertThat(ctxB.getUserId()).isEqualTo(USER_B);
        assertThat(ctxB.getCurrentMood()).isNull();
        assertThat(ctxB.getCurrentEmotion()).isNull();
        assertThat(ctxB.getMoodEntryCount()).isEqualTo(0);
    }
}
