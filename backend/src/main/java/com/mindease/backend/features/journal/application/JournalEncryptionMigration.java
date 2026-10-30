package com.mindease.backend.features.journal.application;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import com.mindease.backend.features.journal.domain.JournalEntry;
import com.mindease.backend.features.journal.domain.JournalEntryRepository;

/**
 * Encrypts journal rows written before field-level encryption existed.
 *
 * <p>Runs once at startup and is idempotent: values that already carry the
 * {@code enc:v1:} prefix are skipped. The plaintext is preserved - only its
 * stored representation changes - so no user content is lost or altered.</p>
 */
@Component
public class JournalEncryptionMigration implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(JournalEncryptionMigration.class);

    private final JournalEntryRepository repository;
    private final JournalCipher cipher;
    private final boolean enabled;

    public JournalEncryptionMigration(
            JournalEntryRepository repository,
            JournalCipher cipher,
            @Value("${mindease.journal.migrate-plaintext:true}") boolean enabled) {
        this.repository = repository;
        this.cipher = cipher;
        this.enabled = enabled;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!enabled || !cipher.isEnabled()) {
            return;
        }
        List<JournalEntry> entries = repository.findAll();
        int migrated = 0;
        for (JournalEntry entry : entries) {
            boolean changed = false;
            if (!cipher.isEncrypted(entry.getTitle())) {
                entry.setTitle(cipher.encrypt(entry.getTitle()));
                changed = changed || entry.getTitle() != null;
            }
            if (!cipher.isEncrypted(entry.getContent())) {
                entry.setContent(cipher.encrypt(entry.getContent()));
                changed = changed || entry.getContent() != null;
            }
            JournalEntry.AiAnalysis ai = entry.getAiAnalysis();
            if (ai != null) {
                if (ai.getSummary() != null && !cipher.isEncrypted(ai.getSummary())) {
                    ai.setSummary(cipher.encrypt(ai.getSummary()));
                    changed = true;
                }
                if (ai.getEmotionalThemes() != null
                        && !cipher.isEncrypted(ai.getEmotionalThemes())) {
                    ai.setEmotionalThemes(cipher.encrypt(ai.getEmotionalThemes()));
                    changed = true;
                }
                if (ai.getReflectionPrompt() != null
                        && !cipher.isEncrypted(ai.getReflectionPrompt())) {
                    ai.setReflectionPrompt(cipher.encrypt(ai.getReflectionPrompt()));
                    changed = true;
                }
            }
            if (!changed) {
                continue;
            }
            try {
                repository.save(entry);
                migrated++;
            } catch (Exception e) {
                log.warn("journal_encryption_migration_failed id={} reason={}",
                        entry.getId(), e.getMessage());
            }
        }
        if (migrated > 0) {
            log.info("journal_encryption_migrated entries={}", migrated);
        }
    }
}
