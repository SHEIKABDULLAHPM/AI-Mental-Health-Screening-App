package com.mindease.backend.features.journal.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.features.journal.dto.CreateJournalRequest;
import com.mindease.backend.features.journal.dto.UpdateJournalRequest;
import com.mindease.backend.media.MediaService;
import com.mindease.backend.personalization.application.PersonalizationService;

/**
 * Tests verifying complete user isolation for journal operations.
 * Uses Mockito to verify that the service layer enforces ownership
 * at every CRUD operation and that cross-user access is blocked.
 */
@ExtendWith(MockitoExtension.class)
class JournalOwnershipIntegrationTest {

    @Mock
    private JournalEntryRepository repository;

    @Mock
    private MediaService mediaService;

    @Mock
    private JournalAiClient aiClient;

    @Mock
    private PersonalizationService personalizationService;

    private JournalService journalService;

    private static final String USER_A = "user-a-123";
    private static final String USER_B = "user-b-456";
    private static final String USER_C = "user-c-789";
    private static final String ENTRY_ID = "entry-123";

    @BeforeEach
    void setUp() {
        journalService = new JournalService(repository, mediaService, aiClient, personalizationService);
    }

    // ── Helpers ──

    private JournalEntry buildEntry(String id, String userId, String title, String content) {
        JournalEntry entry = new JournalEntry();
        entry.setId(id);
        entry.setUserId(userId);
        entry.setTitle(title);
        entry.setContent(content);
        entry.setType("text");
        entry.setEmotion("neutral");
        entry.setContentVersion(1);
        entry.setCreatedAt(Instant.now());
        entry.setUpdatedAt(Instant.now());
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setStatus("NOT_REQUESTED");
        entry.setAiAnalysis(ai);
        return entry;
    }

    private CreateJournalRequest createRequest(String title, String content) {
        return new CreateJournalRequest(title, content, "text", "neutral",
                null, null, null, null, null, null, null,
                null, null, null, null);
    }

    // ── CREATE: Verify ownership assignment ──

    @Test
    void createJournal_assignsCorrectUserId() {
        when(repository.save(any())).thenAnswer(inv -> {
            JournalEntry e = inv.getArgument(0);
            if (e.getId() == null) e.setId("generated-id");
            return e;
        });

        CreateJournalRequest request = createRequest("My Entry", "My content");
        var response = journalService.createJournal(USER_A, request);

        // Verify the saved entry has USER_A as userId
        org.mockito.ArgumentCaptor<JournalEntry> captor =
                org.mockito.ArgumentCaptor.forClass(JournalEntry.class);
        verify(repository, atLeastOnce()).save(captor.capture());
        JournalEntry saved = captor.getAllValues().getFirst();
        assertThat(saved.getUserId()).isEqualTo(USER_A);
    }

    // ── READ: Cross-user isolation ──

    @Test
    void getJournalById_userACannotAccessUserBJournal() {
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> journalService.getJournalById(USER_A, ENTRY_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    var apiEx = (ApiException) ex;
                    assertThat(apiEx.getStatus().value()).isEqualTo(404);
                });
    }

    @Test
    void getJournalById_userACanAccessOwnJournal() {
        JournalEntry userAEntry = buildEntry(ENTRY_ID, USER_A, "User A Entry", "My thoughts");
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A))
                .thenReturn(Optional.of(userAEntry));

        var response = journalService.getJournalById(USER_A, ENTRY_ID);
        assertThat(response.title()).isEqualTo("User A Entry");
    }

    @Test
    void getJournalById_nonexistentJournal_returnsNotFound() {
        when(repository.findByIdAndUserId("nonexistent", USER_A)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> journalService.getJournalById(USER_A, "nonexistent"))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> assertThat(((ApiException) ex).getStatus().value()).isEqualTo(404));
    }

    // ── LIST: User isolation via repository calls ──

    @Test
    void listJournals_passesUserIdToRepository() {
        List<JournalEntry> userAEntries = List.of(
                buildEntry("a1", USER_A, "A Entry 1", "Content A1"),
                buildEntry("a2", USER_A, "A Entry 2", "Content A2"));
        when(repository.findByUserIdOrderByCreatedAtDesc(eq(USER_A), any())).thenReturn(userAEntries);
        when(repository.countByUserId(eq(USER_A))).thenReturn(2L);

        var result = journalService.getJournalEntries(USER_A, 0, 50, null, null);

        assertThat(result.entries()).hasSize(2);
        assertThat(result.total()).isEqualTo(2);
        // Verify USER_A's ID was passed to repository
        verify(repository).findByUserIdOrderByCreatedAtDesc(eq(USER_A), any());
        verify(repository).countByUserId(eq(USER_A));
    }

    @Test
    void listJournals_userBQuery_doesNotLeakUserAData() {
        // Simulate: when USER_B queries, repository only returns USER_B's entries
        List<JournalEntry> userBEntries = List.of(
                buildEntry("b1", USER_B, "B Entry 1", "Content B1"));
        when(repository.findByUserIdOrderByCreatedAtDesc(eq(USER_B), any())).thenReturn(userBEntries);
        when(repository.countByUserId(eq(USER_B))).thenReturn(1L);

        var result = journalService.getJournalEntries(USER_B, 0, 50, null, null);

        assertThat(result.entries()).hasSize(1);
        assertThat(result.entries().get(0).title()).isEqualTo("B Entry 1");
        // Verify only USER_B's ID was passed
        verify(repository).findByUserIdOrderByCreatedAtDesc(eq(USER_B), any());
    }

    @Test
    void search_passesUserIdToRepository() {
        List<JournalEntry> searchResults = List.of(
                buildEntry("s1", USER_A, "A Meditation", "Meditation content"));
        when(repository.searchByUserIdAndText(eq(USER_A), any(), any())).thenReturn(searchResults);

        var result = journalService.getJournalEntries(USER_A, 0, 50, null, "meditation");

        assertThat(result.entries()).hasSize(1);
        verify(repository).searchByUserIdAndText(eq(USER_A), any(), any());
    }

    // ── UPDATE: Cross-user protection ──

    @Test
    void updateJournal_userACannotUpdateUserBJournal() {
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.empty());

        UpdateJournalRequest request = new UpdateJournalRequest(
                "Hacked Title", null, null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        assertThatThrownBy(() -> journalService.updateJournal(USER_A, ENTRY_ID, request))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> assertThat(((ApiException) ex).getStatus().value()).isEqualTo(404));
    }

    @Test
    void updateJournal_userACanUpdateOwnJournal() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "Old Title", "Old Content");
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        UpdateJournalRequest request = new UpdateJournalRequest(
                "New Title", "New Content", null, "happy",
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        var response = journalService.updateJournal(USER_A, ENTRY_ID, request);

        assertThat(response.title()).isEqualTo("New Title");
        assertThat(response.content()).isEqualTo("New Content");
    }

    // ── DELETE: Cross-user protection ──

    @Test
    void deleteJournal_userACannotDeleteUserBJournal() {
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> journalService.deleteJournal(USER_A, ENTRY_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> assertThat(((ApiException) ex).getStatus().value()).isEqualTo(404));
    }

    @Test
    void deleteJournal_userACanDeleteOwnJournal() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "A Entry", "A Content");
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));

        journalService.deleteJournal(USER_A, ENTRY_ID);

        verify(repository).delete(entry);
    }

    // ── MEDIA: User isolation verification ──

    @Test
    void journalMediaKeys_areUserScoped() {
        when(repository.save(any())).thenAnswer(inv -> {
            JournalEntry e = inv.getArgument(0);
            if (e.getId() == null) e.setId("media-id");
            return e;
        });

        CreateJournalRequest request = new CreateJournalRequest(
                "Media Entry", "Has an image", "image", null,
                "journal/" + USER_A + "/images/abc.jpg", "image/jpeg", 1024L,
                null, null, null, null,
                null, null, null, null);

        journalService.createJournal(USER_A, request);

        org.mockito.ArgumentCaptor<JournalEntry> captor =
                org.mockito.ArgumentCaptor.forClass(JournalEntry.class);
        verify(repository, atLeastOnce()).save(captor.capture());
        JournalEntry saved = captor.getAllValues().getFirst();
        assertThat(saved.getImageKey()).startsWith("journal/" + USER_A + "/");
    }

    @Test
    void updateMediaKey_preservesExistingWhenNotChanged() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "Media Entry", "Content");
        entry.setImageKey("journal/" + USER_A + "/images/existing.jpg");
        entry.setImageContentType("image/jpeg");
        entry.setImageSize(2048L);
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        UpdateJournalRequest request = new UpdateJournalRequest(
                null, "Updated content", null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        journalService.updateJournal(USER_A, ENTRY_ID, request);

        assertThat(entry.getImageKey()).isEqualTo("journal/" + USER_A + "/images/existing.jpg");
        assertThat(entry.getContent()).isEqualTo("Updated content");
    }

    @Test
    void removeMediaKey_clearsExistingKey() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "Media Entry", "Content");
        entry.setAudioKey("journal/" + USER_A + "/audio/rec.m4a");
        entry.setAudioContentType("audio/m4a");
        entry.setAudioSize(1024000L);
        entry.setAudioDurationSeconds(60);
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        UpdateJournalRequest request = new UpdateJournalRequest(
                null, null, null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, true, null);

        journalService.updateJournal(USER_A, ENTRY_ID, request);

        assertThat(entry.getAudioKey()).isNull();
        assertThat(entry.getAudioContentType()).isNull();
        assertThat(entry.getAudioSize()).isNull();
        assertThat(entry.getAudioDurationSeconds()).isNull();
    }

    // ── AI STALENESS ──

    @Test
    void updateContent_invalidatesAiAnalysis() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "AI Entry", "Original content");
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setStatus("COMPLETED");
        ai.setEmotion("joy");
        ai.setSentiment("positive");
        entry.setAiAnalysis(ai);
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        UpdateJournalRequest request = new UpdateJournalRequest(
                null, "Modified content", null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        journalService.updateJournal(USER_A, ENTRY_ID, request);

        assertThat(entry.getAiAnalysis().getStatus()).isEqualTo("STALE");
        assertThat(entry.getContentVersion()).isEqualTo(2);
    }

    @Test
    void updateNonContentField_doesNotInvalidateAi() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "AI Entry", "Original content");
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setStatus("COMPLETED");
        ai.setEmotion("joy");
        entry.setAiAnalysis(ai);
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        UpdateJournalRequest request = new UpdateJournalRequest(
                "New Title", null, null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        journalService.updateJournal(USER_A, ENTRY_ID, request);

        assertThat(entry.getAiAnalysis().getStatus()).isEqualTo("COMPLETED");
        assertThat(entry.getContentVersion()).isEqualTo(1);
    }

    // ── VALIDATION ──

    @Test
    void createJournal_rejectsInvalidType() {
        CreateJournalRequest request = createRequest("Bad Entry", "Content");
        // Override type to invalid
        var invalidRequest = new CreateJournalRequest(
                "Bad Entry", "Content", "invalid-type", null,
                null, null, null, null, null, null, null,
                null, null, null, null);

        assertThatThrownBy(() -> journalService.createJournal(USER_A, invalidRequest))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getStatus().value()).isEqualTo(400);
                    assertThat(ex.getMessage()).contains("Invalid journal type");
                });
    }

    @Test
    void createJournal_rejectsEmptyContent() {
        CreateJournalRequest request = new CreateJournalRequest(
                "Empty Entry", "", "text", null,
                null, null, null, null, null, null, null,
                null, null, null, null);

        assertThatThrownBy(() -> journalService.createJournal(USER_A, request))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getStatus().value()).isEqualTo(400);
                    assertThat(ex.getMessage()).contains("must contain");
                });
    }

    @Test
    void updateJournal_rejectsInvalidType() {
        JournalEntry entry = buildEntry(ENTRY_ID, USER_A, "Entry", "Content");
        when(repository.findByIdAndUserId(ENTRY_ID, USER_A)).thenReturn(Optional.of(entry));

        UpdateJournalRequest request = new UpdateJournalRequest(
                null, null, "podcast", null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);

        assertThatThrownBy(() -> journalService.updateJournal(USER_A, ENTRY_ID, request))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> assertThat(((ApiException) ex).getStatus().value()).isEqualTo(400));
    }

    // ── AI ANALYSIS FIELD LENGTH BOUNDS ──

    @Test
    void aiAnalysis_longFields_areTruncated() {
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setStatus("COMPLETED");
        ai.setEmotion("x".repeat(200)); // Exceeds MAX_EMOTION (100)
        ai.setSentiment("y".repeat(200)); // Exceeds MAX_SENTIMENT (100)
        ai.setEmotionalThemes("z".repeat(1000)); // Exceeds MAX_THEMES (500)
        ai.setSummary("s".repeat(3000)); // Exceeds MAX_SUMMARY (2000)
        ai.setReflectionPrompt("r".repeat(3000)); // Exceeds MAX_REFLECTION (2000)

        assertThat(ai.getEmotion()).hasSize(100);
        assertThat(ai.getSentiment()).hasSize(100);
        assertThat(ai.getEmotionalThemes()).hasSize(500);
        assertThat(ai.getSummary()).hasSize(2000);
        assertThat(ai.getReflectionPrompt()).hasSize(2000);
    }

    @Test
    void aiAnalysis_normalFields_notTruncated() {
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setEmotion("joy");
        ai.setSentiment("positive");
        ai.setEmotionalThemes("happiness, gratitude");
        ai.setSummary("Short summary.");
        ai.setReflectionPrompt("What brought this feeling?");

        assertThat(ai.getEmotion()).isEqualTo("joy");
        assertThat(ai.getSentiment()).isEqualTo("positive");
        assertThat(ai.getEmotionalThemes()).isEqualTo("happiness, gratitude");
        assertThat(ai.getSummary()).isEqualTo("Short summary.");
        assertThat(ai.getReflectionPrompt()).isEqualTo("What brought this feeling?");
    }
}
