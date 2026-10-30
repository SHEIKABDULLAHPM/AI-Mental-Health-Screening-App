package com.mindease.backend.features.journal.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.application.ChallengeActivityService;
import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.features.journal.dto.CreateJournalRequest;
import com.mindease.backend.features.journal.dto.JournalListResponse;
import com.mindease.backend.features.journal.dto.JournalResponse;
import com.mindease.backend.features.journal.dto.UpdateJournalRequest;
import com.mindease.backend.media.MediaService;

@ExtendWith(MockitoExtension.class)
class JournalServiceTest {

    @Mock
    private JournalEntryRepository repository;

    @Mock
    private MediaService mediaService;

    @Mock
    private JournalAiClient aiClient;

    @Mock
    private PersonalizationService personalizationService;

    @Mock
    private ChallengeActivityService challengeActivityService;

    private JournalService service;
    private JournalCipher cipher;

    private static final String USER_ID = "user-1";
    private static final String JOURNAL_ID = "journal-1";
    private static final String OTHER_USER_ID = "other-user";

    @BeforeEach
    void setUp() {
        cipher = new JournalCipher("test-journal-encryption-key-0123456789");
        service = new JournalService(repository, mediaService, aiClient,
                personalizationService, challengeActivityService, cipher);
    }

    // --------------------------------------------------------------- createJournal

    @Test
    void createJournalSuccessfully() {
        CreateJournalRequest request = new CreateJournalRequest(
                "Morning Thoughts", "Today was productive", "text", "focused",
                null, null, null, null, null, null, null,
                null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            JournalEntry entry = inv.getArgument(0);
            entry.setId(JOURNAL_ID);
            return entry;
        });

        JournalResponse response = service.createJournal(USER_ID, request);

        assertThat(response.id()).isEqualTo(JOURNAL_ID);
        assertThat(response.title()).isEqualTo("Morning Thoughts");
        assertThat(response.content()).isEqualTo("Today was productive");
        assertThat(response.type()).isEqualTo("text");
        assertThat(response.emotion()).isEqualTo("focused");
        // AI analysis runs async; at least the initial save must happen
        verify(repository, atLeastOnce()).save(any(JournalEntry.class));
    }

    @Test
    void createJournalVoiceType() {
        CreateJournalRequest request = new CreateJournalRequest(
                "Voice Note", "Spoken thoughts", "voice", "reflective",
                null, null, null, "voice-audio-key", "audio/mpeg", 1024000L, 120,
                null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            JournalEntry entry = inv.getArgument(0);
            entry.setId(JOURNAL_ID);
            return entry;
        });

        JournalResponse response = service.createJournal(USER_ID, request);

        assertThat(response.type()).isEqualTo("voice");
        assertThat(response.audioKey()).isEqualTo("voice-audio-key");
    }

    @Test
    void createJournalImageType() {
        CreateJournalRequest request = new CreateJournalRequest(
                "Photo Journal", "Captured a moment", "image", "nostalgic",
                "image-key-1", "image/jpeg", 2048000L, null, null, null, null,
                null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            JournalEntry entry = inv.getArgument(0);
            entry.setId(JOURNAL_ID);
            return entry;
        });

        JournalResponse response = service.createJournal(USER_ID, request);

        assertThat(response.type()).isEqualTo("image");
        assertThat(response.imageKey()).isEqualTo("image-key-1");
    }

    @Test
    void createJournalRejectsInvalidType() {
        CreateJournalRequest request = new CreateJournalRequest(
                "Bad Entry", "Some content", "podcast", "neutral",
                null, null, null, null, null, null, null,
                null, null, null, null);

        assertThatThrownBy(() -> service.createJournal(USER_ID, request))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.BAD_REQUEST);
                    assertThat(ex.getMessage()).contains("Invalid journal type");
                });
        verify(repository, never()).save(any());
    }

    // --------------------------------------------------------------- getJournalEntries

    @Test
    void getJournalEntriesPaginated() {
        List<JournalEntry> entries = List.of(
                createJournalEntity("j-3", USER_ID, "text", "Entry 3"),
                createJournalEntity("j-2", USER_ID, "text", "Entry 2"),
                createJournalEntity("j-1", USER_ID, "text", "Entry 1"));
        when(repository.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any())).thenReturn(entries);

        when(repository.countByUserId(eq(USER_ID))).thenReturn(3L);

        JournalListResponse result = service.getJournalEntries(USER_ID, 0, 10, null, null);

        assertThat(result.entries()).hasSize(3);
        assertThat(result.entries().get(0).title()).isEqualTo("Entry 3");
        assertThat(result.entries().get(1).title()).isEqualTo("Entry 2");
        assertThat(result.entries().get(2).title()).isEqualTo("Entry 1");
        assertThat(result.total()).isEqualTo(3);
        verify(repository).findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any());
    }

    @Test
    void getJournalEntriesWithTypeFilter() {
        List<JournalEntry> voiceEntries = List.of(
                createJournalEntity("v-1", USER_ID, "voice", "Voice Note 1"),
                createJournalEntity("v-2", USER_ID, "voice", "Voice Note 2"));
        when(repository.findByUserIdAndTypeOrderByCreatedAtDesc(eq(USER_ID), eq("voice"), any()))
                .thenReturn(voiceEntries);

        when(repository.countByUserIdAndType(eq(USER_ID), eq("voice"))).thenReturn(2L);

        JournalListResponse result = service.getJournalEntries(USER_ID, 0, 10, "voice", null);

        assertThat(result.entries()).hasSize(2);
        assertThat(result.entries()).allMatch(e -> e.type().equals("voice"));
        verify(repository).findByUserIdAndTypeOrderByCreatedAtDesc(eq(USER_ID), eq("voice"), any());
    }

    @Test
    void getJournalEntriesWithSearch() {
        List<JournalEntry> searchResults = List.of(
                createJournalEntity("s-1", USER_ID, "text", "Meditation Experience"));
        when(repository.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any()))
                .thenReturn(searchResults);

        JournalListResponse result = service.getJournalEntries(USER_ID, 0, 10, null, "meditation");

        assertThat(result.entries()).hasSize(1);
        assertThat(result.entries().get(0).title()).isEqualTo("Meditation Experience");
        verify(repository).findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any());
    }

    @Test
    void searchCoversTheWholeArchiveNotOnlyTheNewestWindow() {
        // A full first chunk with no match: the old "newest 1,000" scan would
        // only ever have seen rows like these and reported no result.
        List<JournalEntry> firstChunk = new ArrayList<>();
        for (int i = 0; i < 500; i++) {
            firstChunk.add(createJournalEntity("new-" + i, USER_ID, "text", "Recent #" + i));
        }
        List<JournalEntry> secondChunk = List.of(
                createJournalEntity("old-1", USER_ID, "text", "Childhood memory"));
        when(repository.findByUserIdOrderByCreatedAtDesc(eq(USER_ID), any()))
                .thenAnswer(inv -> ((Pageable) inv.getArgument(1)).getPageNumber() == 0
                        ? firstChunk
                        : secondChunk);

        JournalListResponse result = service.getJournalEntries(USER_ID, 0, 10, null, "childhood");

        assertThat(result.total()).isEqualTo(1);
        assertThat(result.entries()).hasSize(1);
        assertThat(result.entries().get(0).id()).isEqualTo("old-1");
    }

    @Test
    void getJournalEntriesInvalidTypeFilter() {
        assertThatThrownBy(() -> service.getJournalEntries(USER_ID, 0, 10, "podcast", null))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.BAD_REQUEST);
                    assertThat(ex.getMessage()).contains("Invalid journal type filter");
                });
    }

    // --------------------------------------------------------------- getJournalById

    @Test
    void getJournalByIdWithOwnershipValidation() {
        JournalEntry entry = createJournalEntity(JOURNAL_ID, USER_ID, "text", "My Entry");
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(entry));

        JournalResponse response = service.getJournalById(USER_ID, JOURNAL_ID);

        assertThat(response.id()).isEqualTo(JOURNAL_ID);
        assertThat(response.title()).isEqualTo("My Entry");
    }

    @Test
    void getJournalByIdThrowsNotFoundForOtherUsersJournal() {
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getJournalById(USER_ID, JOURNAL_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.NOT_FOUND);
                    assertThat(ex.getMessage()).contains("Journal entry not found");
                });
    }

    @Test
    void getJournalByIdThrowsNotFoundWhenMissing() {
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getJournalById(USER_ID, JOURNAL_ID))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------------- updateJournal

    @Test
    void updateJournalSuccessfully() {
        JournalEntry entry = createJournalEntity(JOURNAL_ID, USER_ID, "text", "Old Title");
        entry.setContent("Old content");
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenReturn(entry);

        UpdateJournalRequest request = new UpdateJournalRequest(
                "New Title", "New content", null, "inspired",
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        JournalResponse response = service.updateJournal(USER_ID, JOURNAL_ID, request);

        assertThat(response.title()).isEqualTo("New Title");
        assertThat(response.content()).isEqualTo("New content");
        assertThat(response.emotion()).isEqualTo("inspired");
        // AI analysis runs async; at least the initial save must happen
        verify(repository, atLeastOnce()).save(any(JournalEntry.class));
    }

    @Test
    void updateJournalPartialUpdate() {
        JournalEntry entry = createJournalEntity(JOURNAL_ID, USER_ID, "text", "Original Title");
        entry.setContent("Original content");
        entry.setEmotion("calm");
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenReturn(entry);

        UpdateJournalRequest request = new UpdateJournalRequest(
                "Updated Title", null, null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        JournalResponse response = service.updateJournal(USER_ID, JOURNAL_ID, request);

        assertThat(response.title()).isEqualTo("Updated Title");
        assertThat(response.content()).isEqualTo("Original content");
        assertThat(response.emotion()).isEqualTo("calm");
    }

    @Test
    void updateJournalRejectsInvalidType() {
        JournalEntry entry = createJournalEntity(JOURNAL_ID, USER_ID, "text", "Entry");
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(entry));

        UpdateJournalRequest request = new UpdateJournalRequest(
                null, null, "podcast", null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        assertThatThrownBy(() -> service.updateJournal(USER_ID, JOURNAL_ID, request))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.BAD_REQUEST);
                    assertThat(ex.getMessage()).contains("Invalid journal type");
                });
    }

    @Test
    void updateJournalThrowsNotFoundForOtherUsersJournal() {
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.empty());

        UpdateJournalRequest request = new UpdateJournalRequest(
                "New", null, null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        assertThatThrownBy(() -> service.updateJournal(USER_ID, JOURNAL_ID, request))
                .isInstanceOf(ApiException.class)
                .extracting(ex -> ((ApiException) ex).getCode())
                .isEqualTo(ErrorCode.NOT_FOUND);
    }

    // --------------------------------------------------------------- deleteJournal

    @Test
    void deleteJournalSuccessfully() {
        JournalEntry entry = createJournalEntity(JOURNAL_ID, USER_ID, "text", "To Delete");
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(entry));

        service.deleteJournal(USER_ID, JOURNAL_ID);

        verify(repository).delete(entry);
    }

    @Test
    void deleteJournalThrowsNotFoundForOtherUsersJournal() {
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deleteJournal(USER_ID, JOURNAL_ID))
                .isInstanceOf(ApiException.class)
                .satisfies(ex -> {
                    assertThat(((ApiException) ex).getCode()).isEqualTo(ErrorCode.NOT_FOUND);
                    assertThat(ex.getMessage()).contains("Journal entry not found");
                });
        verify(repository, never()).delete(any());
    }

    // ------------------------------------------------------------- encryption

    @Test
    void journalTextIsEncryptedAtRestAndDecryptedOnRead() {
        CreateJournalRequest request = new CreateJournalRequest(
                "Private title", "A very private journal body", "text", null,
                null, null, null, null, null, null, null,
                null, null, null, null);
        when(repository.save(any())).thenAnswer(inv -> {
            JournalEntry entry = inv.getArgument(0);
            entry.setId(JOURNAL_ID);
            return entry;
        });

        JournalResponse response = service.createJournal(USER_ID, request);

        org.mockito.ArgumentCaptor<JournalEntry> saved =
                org.mockito.ArgumentCaptor.forClass(JournalEntry.class);
        verify(repository).save(saved.capture());
        assertThat(saved.getValue().getTitle()).startsWith(JournalCipher.PREFIX);
        assertThat(saved.getValue().getContent()).startsWith(JournalCipher.PREFIX);
        assertThat(saved.getValue().getContent()).doesNotContain("very private");
        // The API response is always plaintext for the owner.
        assertThat(response.title()).isEqualTo("Private title");
        assertThat(response.content()).isEqualTo("A very private journal body");
    }

    @Test
    void legacyPlaintextRowsStayReadable() {
        JournalEntry legacy = createJournalEntity(JOURNAL_ID, USER_ID, "text", "Old entry");
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(legacy));

        JournalResponse response = service.getJournalById(USER_ID, JOURNAL_ID);

        assertThat(response.title()).isEqualTo("Old entry");
        assertThat(response.content()).contains("Old entry");
    }

    @Test
    void updateComparesDecryptedContentAndReEncrypts() {
        JournalEntry entry = createJournalEntity(JOURNAL_ID, USER_ID, "text", "Title");
        entry.setContent(cipher.encrypt("original body"));
        when(repository.findByIdAndUserId(JOURNAL_ID, USER_ID)).thenReturn(Optional.of(entry));
        when(repository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        UpdateJournalRequest request = new UpdateJournalRequest(
                "Title", "changed body", null, null,
                null, null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        JournalResponse response = service.updateJournal(USER_ID, JOURNAL_ID, request);

        assertThat(response.content()).isEqualTo("changed body");
        assertThat(entry.getContent()).startsWith(JournalCipher.PREFIX);
        assertThat(entry.getContent()).isNotEqualTo("changed body");
    }

    // --------------------------------------------------------------- helpers

    private static JournalEntry createJournalEntity(String id, String userId, String type, String title) {
        JournalEntry entry = new JournalEntry();
        entry.setId(id);
        entry.setUserId(userId);
        entry.setTitle(title);
        entry.setContent("Test content for " + title);
        entry.setType(type);
        entry.setEmotion("neutral");
        entry.setCreatedAt(Instant.now());
        entry.setUpdatedAt(Instant.now());
        return entry;
    }
}
