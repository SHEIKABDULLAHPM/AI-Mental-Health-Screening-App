package com.mindease.backend.features.journal.application;

import java.time.Instant;
import java.util.List;
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
    private static final ExecutorService AI_EXECUTOR = Executors.newFixedThreadPool(2);

    private final JournalEntryRepository repository;
    private final MediaService mediaService;
    private final JournalAiClient aiClient;
    private final PersonalizationService personalizationService;

    public JournalService(JournalEntryRepository repository, MediaService mediaService,
            JournalAiClient aiClient, PersonalizationService personalizationService) {
        this.repository = repository;
        this.mediaService = mediaService;
        this.aiClient = aiClient;
        this.personalizationService = personalizationService;
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
        return JournalResponse.from(entry, imageUrl, audioUrl, videoUrl);
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
        entry.setTitle(request.title());
        entry.setContent(request.content() != null ? request.content() : "");
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

        return resolve(saved, userId);
    }

    public JournalListResponse getJournalEntries(String userId, int page, int size,
            String type, String search) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), MAX_PAGE_SIZE);
        Pageable pageable = PageRequest.of(safePage, safeSize);

        List<JournalEntry> entries;
        long totalCount;

        if (type != null && !type.isBlank()) {
            if (!VALID_TYPES.contains(type)) {
                throw new ApiException(ErrorCode.BAD_REQUEST,
                        "Invalid journal type filter. Must be one of: text, voice, image, video");
            }
            entries = repository.findByUserIdAndTypeOrderByCreatedAtDesc(userId, type, pageable);
            totalCount = repository.countByUserIdAndType(userId, type);
        } else if (search != null && !search.isBlank()) {
            String query = search.trim();
            if (query.length() > 200) query = query.substring(0, 200);
            // Pattern.quote wraps the query in \Q…\E for a safe literal regex match
            query = java.util.regex.Pattern.quote(query);
            entries = repository.searchByUserIdAndText(userId, query, pageable);
            // Count for search results is the size of this page (approximate)
            totalCount = entries.size();
        } else {
            entries = repository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
            totalCount = repository.countByUserId(userId);
        }

        List<JournalResponse> responseList = entries.stream()
                .map(e -> resolve(e, userId))
                .toList();

        long endOffset = (long) (safePage + 1) * safeSize;
        boolean hasMore = endOffset < totalCount;

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
            entry.setTitle(request.title());
        }
        if (request.content() != null) {
            if (!request.content().equals(entry.getContent())) {
                contentChanged = true;
            }
            entry.setContent(request.content());
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
                String title = current.getTitle();
                String content = current.getContent();
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
