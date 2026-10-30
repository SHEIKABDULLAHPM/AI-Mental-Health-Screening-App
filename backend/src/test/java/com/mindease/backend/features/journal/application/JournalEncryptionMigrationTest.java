package com.mindease.backend.features.journal.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;

/**
 * Legacy plaintext rows must be sealed exactly once. Re-running the migration
 * (every startup) must not double-encrypt or rewrite untouched rows.
 */
@ExtendWith(MockitoExtension.class)
class JournalEncryptionMigrationTest {

    private static final String KEY = "migration-test-key-0123456789abcdef";

    @Mock
    private JournalEntryRepository repository;

    private JournalCipher cipher;
    private JournalEncryptionMigration migration;

    @BeforeEach
    void setUp() {
        cipher = new JournalCipher(KEY);
        migration = new JournalEncryptionMigration(repository, cipher, true);
    }

    private JournalEntry entry(String id, String title, String content) {
        JournalEntry entry = new JournalEntry();
        entry.setId(id);
        entry.setUserId("user-1");
        entry.setTitle(title);
        entry.setContent(content);
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setStatus("COMPLETED");
        ai.setSummary("summary text");
        ai.setEmotionalThemes("themes");
        ai.setReflectionPrompt("prompt");
        entry.setAiAnalysis(ai);
        return entry;
    }

    @Test
    void encryptsLegacyPlaintextRow() {
        JournalEntry legacy = entry("j1", "Private title", "Private body");
        when(repository.findAll()).thenReturn(List.of(legacy));

        migration.run(null);

        assertThat(legacy.getTitle()).startsWith(JournalCipher.PREFIX);
        assertThat(legacy.getContent()).startsWith(JournalCipher.PREFIX);
        assertThat(legacy.getAiAnalysis().getSummary()).startsWith(JournalCipher.PREFIX);
        assertThat(cipher.decrypt(legacy.getContent())).isEqualTo("Private body");
        verify(repository).save(legacy);
    }

    @Test
    void alreadyEncryptedRowsAreNotRewritten() {
        JournalEntry sealed = entry("j2", cipher.encrypt("Title"), cipher.encrypt("Body"));
        JournalEntry.AiAnalysis ai = sealed.getAiAnalysis();
        ai.setSummary(cipher.encrypt("summary text"));
        ai.setEmotionalThemes(cipher.encrypt("themes"));
        ai.setReflectionPrompt(cipher.encrypt("prompt"));
        when(repository.findAll()).thenReturn(List.of(sealed));

        migration.run(null);

        verify(repository, never()).save(sealed);
        assertThat(cipher.decrypt(sealed.getContent())).isEqualTo("Body");
    }

    @Test
    void nullAnalysisFieldsDoNotTriggerAWrite() {
        JournalEntry sealed = entry("j3", cipher.encrypt("Title"), cipher.encrypt("Body"));
        sealed.getAiAnalysis().setSummary(null);
        sealed.getAiAnalysis().setEmotionalThemes(null);
        sealed.getAiAnalysis().setReflectionPrompt(null);
        when(repository.findAll()).thenReturn(List.of(sealed));

        migration.run(null);

        verify(repository, never()).save(sealed);
    }

    @Test
    void disabledMigrationDoesNothing() {
        JournalEncryptionMigration disabled =
                new JournalEncryptionMigration(repository, cipher, false);
        JournalEntry legacy = entry("j4", "Title", "Body");

        disabled.run(null);

        verify(repository, never()).findAll();
        assertThat(legacy.getTitle()).isEqualTo("Title");
    }
}
