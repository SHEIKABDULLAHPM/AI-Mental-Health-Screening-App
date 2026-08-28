package com.mindease.backend.personalization.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageRequest;

import com.mindease.backend.coach.domain.CoachMemory;
import com.mindease.backend.coach.domain.CoachMemoryRepository;
import com.mindease.backend.coach.domain.Conversation;
import com.mindease.backend.coach.domain.ConversationRepository;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.mood.application.MoodTrendAnalyzer;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteraction;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;

@ExtendWith(MockitoExtension.class)
class PersonalizationContextBuilderTest {

    @Mock private MoodEntryRepository moodRepo;
    @Mock private JournalEntryRepository journalRepo;
    @Mock private RecommendationInteractionRepository interactionRepo;
    @Mock private ConversationRepository conversationRepo;
    @Mock private CoachMemoryRepository memoryRepo;
    @Mock private WellnessProfileRepository wellnessRepo;
    @Mock private MoodTrendAnalyzer moodTrendAnalyzer;

    private PersonalizationContextBuilder builder;

    private static final String USER_ID = "user-1";

    @BeforeEach
    void setUp() {
        builder = new PersonalizationContextBuilder(
                moodRepo, journalRepo, interactionRepo, conversationRepo,
                memoryRepo, wellnessRepo, moodTrendAnalyzer);
    }

    @Test
    void build_withEmptyData_producesMinimalContext() {
        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.getUserId()).isEqualTo(USER_ID);
        assertThat(ctx.getMoodEntryCount()).isEqualTo(0);
        assertThat(ctx.isJournalAvailable()).isFalse();
        assertThat(ctx.isCoachActive()).isFalse();
        assertThat(ctx.getPersonalizationSummary()).contains("Start tracking your mood");
    }

    @Test
    void build_withMoodData_populatesMoodContext() {
        MoodEntry mood = createMood("happy", "joy");
        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of(mood));
        when(moodRepo.findByUserIdAndRecordedAtAfterOrderByRecordedAtDesc(eq(USER_ID), any()))
                .thenReturn(List.of(mood));
        when(moodTrendAnalyzer.analyzeTrend(any())).thenReturn(
                Map.of("direction", "improving", "description", "Trending up"));
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.getCurrentMood()).isEqualTo("happy");
        assertThat(ctx.getCurrentEmotion()).isEqualTo("joy");
        assertThat(ctx.getMoodTrend()).isEqualTo("improving");
        assertThat(ctx.getMoodEntryCount()).isEqualTo(1);
        assertThat(ctx.getDominantMood()).isEqualTo("happy");
    }

    @Test
    void build_withJournalData_populatesJournalContext() {
        JournalEntry journal = new JournalEntry();
        journal.setId("j-1");
        journal.setTitle("Reflective day");
        journal.setEmotion("calm");
        JournalEntry.AiAnalysis analysis = new JournalEntry.AiAnalysis();
        analysis.setEmotion("peaceful");
        analysis.setEmotionalThemes("calm, reflective");
        analysis.setSentiment("positive");
        journal.setAiAnalysis(analysis);

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of(journal));
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.isJournalAvailable()).isTrue();
        assertThat(ctx.getRecentJournalCount()).isEqualTo(1);
        assertThat(ctx.getJournalEmotionalThemes()).contains("calm", "peaceful");
        assertThat(ctx.getJournalSentiments()).contains("positive");
    }

    @Test
    void build_withCoachData_populatesCoachContext() {
        Conversation conv = new Conversation();
        conv.setId("c-1");
        conv.setUserId(USER_ID);
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of(conv));

        CoachMemory memory = new CoachMemory();
        memory.setCategory("preference");
        memory.setContent("User prefers morning exercises");
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of(memory));

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.isCoachActive()).isTrue();
        assertThat(ctx.getCoachMemoryCategories()).contains("preference");
    }

    @Test
    void build_withWellnessProfile_populatesWellnessContext() {
        WellnessProfile profile = new WellnessProfile();
        profile.setStressLevel("moderate");
        profile.setSleepQuality("good");
        profile.setPrimaryFocus("stress management");
        profile.setWellnessScore(72);
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.of(profile));

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.getStressLevel()).isEqualTo("moderate");
        assertThat(ctx.getSleepQuality()).isEqualTo("good");
        assertThat(ctx.getPrimaryFocus()).isEqualTo("stress management");
        assertThat(ctx.getWellnessScore()).isEqualTo(72);
    }

    @Test
    void build_isolation_neverMixesUserData() {
        // Verify that userId is always correctly set
        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.getUserId()).isEqualTo(USER_ID);
        assertThat(ctx.getUserId()).isNotEqualTo("other-user");
    }

    @Test
    void build_withInteractionData_populatesRecommendationContext() {
        RecommendationInteraction interaction = new RecommendationInteraction();
        interaction.setUserId(USER_ID);
        interaction.setContentId("rec-1");
        interaction.setInteractionType("COMPLETED");
        when(interactionRepo.findByUserIdAndCreatedAtAfterOrderByCreatedAtDesc(
                eq(USER_ID), any())).thenReturn(List.of(interaction));

        when(moodRepo.findByUserIdOrderByRecordedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(journalRepo.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(eq(USER_ID), any(PageRequest.class)))
                .thenReturn(List.of());
        when(memoryRepo.findByUserIdOrderByConfidenceDesc(USER_ID)).thenReturn(List.of());
        when(wellnessRepo.findFirstByUserIdOrderByCreatedAtDesc(USER_ID))
                .thenReturn(java.util.Optional.empty());

        PersonalizedContext ctx = builder.build(USER_ID);

        assertThat(ctx.getRecentlyCompletedRecommendations()).contains("rec-1");
    }

    // ── Helpers ──

    private MoodEntry createMood(String mood, String emotion) {
        MoodEntry entry = new MoodEntry();
        entry.setUserId(USER_ID);
        entry.setMood(mood);
        entry.setEmotion(emotion);
        entry.setRecordedAt(Instant.now());
        entry.setCreatedAt(Instant.now());
        return entry;
    }
}
