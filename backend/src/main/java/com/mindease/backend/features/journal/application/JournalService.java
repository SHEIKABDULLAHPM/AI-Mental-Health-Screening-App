package com.mindease.backend.features.journal.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

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

@Service
public class JournalService {

    private static final Logger log = LoggerFactory.getLogger(JournalService.class);
    private static final Set<String> VALID_TYPES = Set.of("text", "voice", "image", "video");
    private static final int MAX_PAGE_SIZE = 50;
    /**
     * Search runs after decryption because content is encrypted at rest, so it
     * pages through the caller's own entries in chunks. The whole archive is
     * searched — there is no "newest N" window — while memory stays bounded to
     * one chunk at a time.
     */
    private static final int SEARCH_PAGE_SIZE = 500;
    /**
     * Hard per-request ceiling. A single search never decrypts more than this
     * many rows, so an adversarially large archive cannot be turned into an
     * unbounded CPU/memory sink. Reaching it makes {@code hasMore} true rather
     * than silently returning a wrong total.
     */
    private static final int MAX_SEARCH_SCAN = 20_000;
    private static final ExecutorService AI_EXECUTOR = Executors.newFixedThreadPool(2);

    private final JournalEntryRepository repository;
    private final MediaService mediaService;
    private final JournalAiClient aiClient;
    private final PersonalizationService personalizationService;
    private final ChallengeActivityService challengeActivityService;
    private final JournalCipher cipher;

    public JournalService(JournalEntryRepository repository, MediaService mediaService,
            JournalAiClient aiClient, PersonalizationService personalizationService,
            ChallengeActivityService challengeActivityService, JournalCipher cipher) {
        this.repository = repository;
        this.mediaService = mediaService;
        this.aiClient = aiClient;
        this.personalizationService = personalizationService;
        this.challengeActivityService = challengeActivityService;
        this.cipher = cipher;
    }

    /**
     * Resolve presigned media URLs for a journal entry.
     * Only resolves keys belonging to the given userId for security.
     */
    private JournalResponse resolve(JournalEntry entry, String userId) {
        String imageUrl = null;
        String audioUrl = null;
        String videoUrl = null;
        if (entry.getImageKey() != null && !entry.getImageKey().isBlank()
                && entry.getImageKey().startsWith("journal/" + userId + "/")) {
            imageUrl = mediaService.getPresignedUrl(entry.getImageKey());
        }
        if (entry.getAudioKey() != null && !entry.getAudioKey().isBlank()
                && entry.getAudioKey().startsWith("journal/" + userId + "/")) {
            audioUrl = mediaService.getPresignedUrl(entry.getAudioKey());
        }
        if (entry.getVideoKey() != null && !entry.getVideoKey().isBlank()
                && entry.getVideoKey().startsWith("journal/" + userId + "/")) {
            videoUrl = mediaService.getPresignedUrl(entry.getVideoKey());
        }
        return JournalResponse.from(entry, imageUrl, audioUrl, videoUrl, cipher::decrypt);
    }

    public JournalResponse createJournal(String userId, CreateJournalRequest request) {
        if (!VALID_TYPES.contains(request.type())) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Invalid journal type. Must be one of: text, voice, image, video");
        }

        // Validate that meaningful content exists
        boolean hasText = request.content() != null && !request.content().isBlank();
        boolean hasImage = request.imageKey() != null && !request.imageKey().isBlank();
        boolean hasAudio = request.audioKey() != null && !request.audioKey().isBlank();
        boolean hasVideo = request.videoKey() != null && !request.videoKey().isBlank();
        if (!hasText && !hasImage && !hasAudio && !hasVideo) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Journal entry must contain text, an image, a voice recording, or a video.");
        }

        JournalEntry entry = new JournalEntry();
        entry.setUserId(userId);
        // Title and body are sealed at rest; the API always returns plaintext.
        entry.setTitle(cipher.encrypt(request.title()));
        entry.setContent(cipher.encrypt(request.content() != null ? request.content() : ""));
        entry.setType(request.type());
        entry.setEmotion(request.emotion());
        entry.setImageKey(request.imageKey());
        entry.setImageContentType(request.imageContentType());
        entry.setImageSize(request.imageSize());
        entry.setAudioKey(request.audioKey());
        entry.setAudioContentType(request.audioContentType());
        entry.setAudioSize(request.audioSize());
        entry.setAudioDurationSeconds(request.audioDurationSeconds());
        entry.setVideoKey(request.videoKey());
        entry.setVideoContentType(request.videoContentType());
        entry.setVideoSize(request.videoSize());
        entry.setVideoDurationSeconds(request.videoDurationSeconds());
        entry.setContentVersion(1);
        entry.setCreatedAt(Instant.now());
        entry.setUpdatedAt(Instant.now());

        // Initialize AI analysis as NOT_REQUESTED
        JournalEntry.AiAnalysis ai = new JournalEntry.AiAnalysis();
        ai.setStatus("NOT_REQUESTED");
        entry.setAiAnalysis(ai);

        JournalEntry saved = repository.save(entry);
        triggerAiAnalysis(saved);

        // Trigger personalization context refresh (fire-and-forget)
        personalizationService.recordFeedback(userId, "JOURNAL_CREATED", saved.getId(),
                "journal", java.util.Map.of("type", request.type()));

        // Advance any matching started journaling challenges (fire-and-forget)
        challengeActivityService.onJournalCreated(userId, saved.getId(), null);

        return resolve(saved, userId);
    }

    public JournalListResponse getJournalEntries(String userId, int page, int size,
            String type, String search) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), MAX_PAGE_SIZE);
        Pageable pageable = PageRequest.of(safePage, safeSize);

        List<JournalEntry> entries;
        long totalCount;
        // True when a search hit the per-request scan ceiling, so the caller is
        // told more may exist instead of being shown a silently wrong total.
        boolean searchScanCapped = false;

        if (type != null && !type.isBlank()) {
            if (!VALID_TYPES.contains(type)) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Invalid journal type filter. Must be one of: text, voice, image, video");
            }
            entries = repository.findByUserIdAndTypeOrderByCreatedAtDesc(userId, type, pageable);
            totalCount = repository.countByUserIdAndType(userId, type);
        } else if (search != null && !search.isBlank()) {
            String needle = search.trim().toLowerCase(Locale.ROOT);
            if (needle.length() > 200) needle = needle.substring(0, 200);
            // Content is encrypted at rest, so Mongo cannot regex it. Page
            // through this user's own entries and filter after decryption;
            // another user's rows are never read.
            List<JournalEntry> matched = new ArrayList<>();
            for (int offset = 0;; offset += SEARCH_PAGE_SIZE) {
                if (offset >= MAX_SEARCH_SCAN) {
                    searchScanCapped = true;
                    break;
                }
                List<JournalEntry> chunk = repository.findByUserIdOrderByCreatedAtDesc(
                        userId, PageRequest.of(offset / SEARCH_PAGE_SIZE, SEARCH_PAGE_SIZE));
                if (chunk.isEmpty()) break;
                for (JournalEntry candidate : chunk) {
                    if (containsIgnoreCase(cipher.decrypt(candidate.getTitle()), needle)
                            || containsIgnoreCase(cipher.decrypt(candidate.getContent()), needle)) {
                        matched.add(candidate);
                    }
                }
                if (chunk.size() < SEARCH_PAGE_SIZE) break;
            }
            totalCount = matched.size();
            if (searchScanCapped) {
                log.warn("journal_search_scan_capped userId={} limit={}", userId, MAX_SEARCH_SCAN);
            }
            int fromIndex = Math.min(safePage * safeSize, matched.size());
            int toIndex = Math.min(fromIndex + safeSize, matched.size());
            entries = matched.subList(fromIndex, toIndex);
        } else {
            entries = repository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
            totalCount = repository.countByUserId(userId);
        }

        List<JournalResponse> responseList = entries.stream()
                .map(e -> resolve(e, userId))
                .toList();

        long endOffset = (long) (safePage + 1) * safeSize;
        boolean hasMore = endOffset < totalCount || searchScanCapped;

        return new JournalListResponse(responseList, totalCount, safePage, safeSize, hasMore);
    }

    public JournalResponse getJournalById(String userId, String id) {
        JournalEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Journal entry not found"));
        return resolve(entry, userId);
    }

    public JournalResponse updateJournal(String userId, String id, UpdateJournalRequest request) {
        JournalEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Journal entry not found"));

        boolean contentChanged = false;

        if (request.title() != null) {
            entry.setTitle(cipher.encrypt(request.title()));
        }
        if (request.content() != null) {
            if (!request.content().equals(cipher.decrypt(entry.getContent()))) {
                contentChanged = true;
            }
            entry.setContent(cipher.encrypt(request.content()));
        }
        if (request.type() != null) {
            if (!VALID_TYPES.contains(request.type())) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Invalid journal type. Must be one of: text, voice, image, video");
            }
            entry.setType(request.type());
        }
        if (request.emotion() != null) {
            entry.setEmotion(request.emotion());
        }

        // Media updates
        boolean removeImage = Boolean.TRUE.equals(request.removeImage());
        boolean removeAudio = Boolean.TRUE.equals(request.removeAudio());
        boolean removeVideo = Boolean.TRUE.equals(request.removeVideo());

        if (removeImage) {
            if (entry.getImageKey() != null && !entry.getImageKey().isBlank()) {
                mediaService.delete(entry.getImageKey());
            }
            entry.setImageKey(null);
            entry.setImageContentType(null);
            entry.setImageSize(null);
            contentChanged = true;
        } else if (request.imageKey() != null && !request.imageKey().isBlank()) {
            // Replace image
            if (entry.getImageKey() != null && !entry.getImageKey().isBlank()) {
                mediaService.delete(entry.getImageKey());
            }
            entry.setImageKey(request.imageKey());
            entry.setImageContentType(request.imageContentType());
            entry.setImageSize(request.imageSize());
            contentChanged = true;
        }

        if (removeAudio) {
            if (entry.getAudioKey() != null && !entry.getAudioKey().isBlank()) {
                mediaService.delete(entry.getAudioKey());
            }
            entry.setAudioKey(null);
            entry.setAudioContentType(null);
            entry.setAudioSize(null);
            entry.setAudioDurationSeconds(null);
            contentChanged = true;
        } else if (request.audioKey() != null && !request.audioKey().isBlank()) {
            // Replace audio
            if (entry.getAudioKey() != null && !entry.getAudioKey().isBlank()) {
                mediaService.delete(entry.getAudioKey());
            }
            entry.setAudioKey(request.audioKey());
            entry.setAudioContentType(request.audioContentType());
            entry.setAudioSize(request.audioSize());
            entry.setAudioDurationSeconds(request.audioDurationSeconds());
            contentChanged = true;
        }

        if (removeVideo) {
            if (entry.getVideoKey() != null && !entry.getVideoKey().isBlank()) {
                mediaService.delete(entry.getVideoKey());
            }
            entry.setVideoKey(null);
            entry.setVideoContentType(null);
            entry.setVideoSize(null);
            entry.setVideoDurationSeconds(null);
            contentChanged = true;
        } else if (request.videoKey() != null && !request.videoKey().isBlank()) {
            // Replace video
            if (entry.getVideoKey() != null && !entry.getVideoKey().isBlank()) {
                mediaService.delete(entry.getVideoKey());
            }
            entry.setVideoKey(request.videoKey());
            entry.setVideoContentType(request.videoContentType());
            entry.setVideoSize(request.videoSize());
            entry.setVideoDurationSeconds(request.videoDurationSeconds());
            contentChanged = true;
        }

        // Content versioning: increment and mark AI stale when content changes
        if (contentChanged) {
            entry.incrementContentVersion();
            entry.markAiStale();
        }

        entry.setUpdatedAt(Instant.now());
        try {
            JournalEntry saved = repository.save(entry);
            if (contentChanged) {
                triggerAiAnalysis(saved);
            }
            return resolve(saved, userId);
        } catch (OptimisticLockingFailureException e) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "This entry was modified by another request. Please refresh and try again.");
        }
    }

    public void deleteJournal(String userId, String id) {
        JournalEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Journal entry not found"));

        // Clean up associated media
        if (entry.getImageKey() != null && !entry.getImageKey().isBlank()) {
            mediaService.delete(entry.getImageKey());
        }
        if (entry.getAudioKey() != null && !entry.getAudioKey().isBlank()) {
            mediaService.delete(entry.getAudioKey());
        }
        if (entry.getVideoKey() != null && !entry.getVideoKey().isBlank()) {
            mediaService.delete(entry.getVideoKey());
        }

        repository.delete(entry);
        log.info("journal_deleted userId={} journalId={}", userId, id);
    }

    /**
     * Allow the user to retry a failed or stale AI analysis.
     * Resets the analysis status and re-triggers analysis.
     */
    public JournalResponse retryAiAnalysis(String userId, String id) {
        JournalEntry entry = repository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> ApiException.notFound("Journal entry not found"));

        JournalEntry.AiAnalysis ai = entry.getAiAnalysis();
        if (ai != null && "PROCESSING".equals(ai.getStatus())) {
            throw new ApiException(ErrorCode.CONFLICT, "Analysis is already in progress.");
        }
        if (ai != null && "COMPLETED".equals(ai.getStatus())) {
            // Allow re-analysis — mark current as stale
            entry.markAiStale();
        }

        entry.setUpdatedAt(Instant.now());
        JournalEntry saved = repository.save(entry);
        triggerAiAnalysis(saved);
        return resolve(saved, userId);
    }

    private static boolean containsIgnoreCase(String value, String needle) {
        return value != null && value.toLowerCase(Locale.ROOT).contains(needle);
    }

    private void encryptAnalysis(JournalEntry.AiAnalysis ai) {
        if (ai == null) {
            return;
        }
        ai.setEmotionalThemes(cipher.encrypt(ai.getEmotionalThemes()));
        ai.setSummary(cipher.encrypt(ai.getSummary()));
        ai.setReflectionPrompt(cipher.encrypt(ai.getReflectionPrompt()));
    }

    /**
     * Fire-and-forget AI analysis for journal content.
     * Sets status to PROCESSING, calls AI, persists result.
     * Never throws — AI failure is non-blocking.
     */
    private void triggerAiAnalysis(JournalEntry entry) {
        // Fire-and-forget: run AI analysis asynchronously so it never blocks
        // the HTTP response. Journal CRUD completes instantly.
        final String journalId = entry.getId();

        // Fire async on a dedicated thread pool — do not block the caller
        CompletableFuture.runAsync(() -> {
            try {
                // Re-fetch entry to get the latest state (with correct documentVersion)
                JournalEntry current = repository.findById(journalId).orElse(null);
                if (current == null) return;

                // Compute analysis text from the LATEST entry state (not the stale
                // copy captured before the async dispatch)
                String title = cipher.decrypt(current.getTitle());
                String content = cipher.decrypt(current.getContent());
                String analysisText;
                if (title != null && !title.isBlank()) {
                    analysisText = (content != null && !content.isBlank())
                            ? title + "\n\n" + content : title;
                } else {
                    analysisText = content;
                }
                if (analysisText == null || analysisText.isBlank()) {
                    // For media-only entries without text, set a soft FAILED with a
                    // clear reason — don't fabricate analysis.
                    JournalEntry.AiAnalysis noContent = new JournalEntry.AiAnalysis();
                    noContent.setStatus("FAILED");
                    noContent.setAnalyzedContentVersion(current.getContentVersion());
                    noContent.setAnalyzedAt(java.time.Instant.now());
                    try {
                        current.setAiAnalysis(noContent);
                        repository.save(current);
                    } catch (Exception ex) {
                        log.warn("Failed to set no-content AI status for {}: {}", journalId, ex.getMessage());
                    }
                    return;
                }

                // Set PROCESSING before AI call
                int versionAtStart = current.getContentVersion();
                JournalEntry.AiAnalysis processing = new JournalEntry.AiAnalysis();
                processing.setStatus("PROCESSING");
                processing.setAnalyzedContentVersion(versionAtStart);
                current.setAiAnalysis(processing);
                try {
                    repository.save(current);
                } catch (Exception e) {
                    log.warn("Failed to set AI status to PROCESSING for {}: {}", journalId, e.getMessage());
                }

                // Call AI service
                JournalEntry.AiAnalysis result = aiClient.analyzeJournal(analysisText, current.getContentVersion());
                // The analysis summary/themes/prompt can echo the entry text,
                // so they are sealed with the same key before persistence.
                encryptAnalysis(result);

                // Re-fetch before saving to avoid losing the result on version conflict
                JournalEntry latest = repository.findById(journalId).orElse(null);
                if (latest == null) return;
                // Guard: only persist if content hasn't changed since analysis started
                if (latest.getContentVersion() != versionAtStart) {
                    log.info("AI result skipped for {} — content version changed ({} -> {})",
                            journalId, versionAtStart, latest.getContentVersion());
                    // Mark as STALE so the next trigger picks it up
                    if (latest.getAiAnalysis() == null
                            || "PROCESSING".equals(latest.getAiAnalysis().getStatus())) {
                        JournalEntry.AiAnalysis stale = new JournalEntry.AiAnalysis();
                        stale.setStatus("STALE");
                        stale.setAnalyzedContentVersion(versionAtStart);
                        stale.setAnalyzedAt(java.time.Instant.now());
                        latest.setAiAnalysis(stale);
                        try {
                            repository.save(latest);
                        } catch (Exception ex) {
                            log.warn("Failed to set STALE status for {}: {}", journalId, ex.getMessage());
                        }
                    }
                    return;
                }
                latest.setAiAnalysis(result);
                try {
                    repository.save(latest);
                    log.info("AI analysis completed for journal {}", journalId);
                } catch (org.springframework.dao.OptimisticLockingFailureException e) {
                    log.warn("AI result lost to version conflict for {}: retrying", journalId);
                    // One retry: re-fetch and save again
                    JournalEntry retry = repository.findById(journalId).orElse(null);
                    if (retry != null) {
                        retry.setAiAnalysis(result);
                        try {
                            repository.save(retry);
                            log.info("AI analysis completed (retry) for journal {}", journalId);
                        } catch (Exception ex) {
                            log.warn("AI result lost after retry for {}: {}", journalId, ex.getMessage());
                        }
                    }
                } catch (Exception e) {
                    log.warn("Failed to persist AI analysis result for {}: {}", journalId, e.getMessage());
                }
            } catch (Exception e) {
                log.warn("AI analysis failed for journal {}: {}", journalId, e.getMessage());
            }
        }, AI_EXECUTOR);
    }
}
