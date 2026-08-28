package com.mindease.backend.features.journal.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "journal_entries")
@CompoundIndex(name = "userId_createdAt_idx", def = "{'userId': 1, 'createdAt': -1}")
public class JournalEntry {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String title;
    private String content;
    private String type;
    private String emotion;

    // Media references (object keys, not URLs)
    private String imageKey;
    private String imageContentType;
    private Long imageSize;
    private String audioKey;
    private String audioContentType;
    private Long audioSize;
    private Integer audioDurationSeconds;
    private String videoKey;
    private String videoContentType;
    private Long videoSize;
    private Integer videoDurationSeconds;

    // AI analysis
    private AiAnalysis aiAnalysis;

    // Content versioning for AI staleness detection
    private int contentVersion = 1;

    @Version
    private Long documentVersion;

    private Instant createdAt;
    private Instant updatedAt;

    public JournalEntry() {
    }

    // ── Getters & Setters ──

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getContent() { return content; }
    public void setContent(String content) { this.content = content; }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public String getEmotion() { return emotion; }
    public void setEmotion(String emotion) { this.emotion = emotion; }

    public String getImageKey() { return imageKey; }
    public void setImageKey(String imageKey) { this.imageKey = imageKey; }

    public String getImageContentType() { return imageContentType; }
    public void setImageContentType(String imageContentType) { this.imageContentType = imageContentType; }

    public Long getImageSize() { return imageSize; }
    public void setImageSize(Long imageSize) { this.imageSize = imageSize; }

    public String getAudioKey() { return audioKey; }
    public void setAudioKey(String audioKey) { this.audioKey = audioKey; }

    public String getAudioContentType() { return audioContentType; }
    public void setAudioContentType(String audioContentType) { this.audioContentType = audioContentType; }

    public Long getAudioSize() { return audioSize; }
    public void setAudioSize(Long audioSize) { this.audioSize = audioSize; }

    public Integer getAudioDurationSeconds() { return audioDurationSeconds; }
    public void setAudioDurationSeconds(Integer audioDurationSeconds) { this.audioDurationSeconds = audioDurationSeconds; }

    public String getVideoKey() { return videoKey; }
    public void setVideoKey(String videoKey) { this.videoKey = videoKey; }

    public String getVideoContentType() { return videoContentType; }
    public void setVideoContentType(String videoContentType) { this.videoContentType = videoContentType; }

    public Long getVideoSize() { return videoSize; }
    public void setVideoSize(Long videoSize) { this.videoSize = videoSize; }

    public Integer getVideoDurationSeconds() { return videoDurationSeconds; }
    public void setVideoDurationSeconds(Integer videoDurationSeconds) { this.videoDurationSeconds = videoDurationSeconds; }

    public AiAnalysis getAiAnalysis() { return aiAnalysis; }
    public void setAiAnalysis(AiAnalysis aiAnalysis) { this.aiAnalysis = aiAnalysis; }

    public int getContentVersion() { return contentVersion; }
    public void setContentVersion(int contentVersion) { this.contentVersion = contentVersion; }

    public void incrementContentVersion() { this.contentVersion++; }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }

    /** Mark AI analysis as stale when content changes. */
    public void markAiStale() {
        if (aiAnalysis != null && "COMPLETED".equals(aiAnalysis.getStatus())) {
            aiAnalysis.setStatus("STALE");
        }
    }

    /** Embedded AI analysis result. */
    public static class AiAnalysis {
        private String status; // NOT_REQUESTED, PROCESSING, COMPLETED, FAILED, STALE
        private String emotion;
        private Double emotionConfidence;
        private String sentiment;
        private Double sentimentConfidence;
        private String emotionalThemes;
        private String summary;
        private String reflectionPrompt;
        private String analysisVersion;
        private Integer analyzedContentVersion;
        private Instant analyzedAt;

        public AiAnalysis() {}

        // Max lengths for AI-generated fields to prevent unbounded storage
        private static final int MAX_EMOTION = 100;
        private static final int MAX_SENTIMENT = 100;
        private static final int MAX_THEMES = 500;
        private static final int MAX_SUMMARY = 2000;
        private static final int MAX_REFLECTION = 2000;

        private static String truncate(String s, int max) {
            return (s != null && s.length() > max) ? s.substring(0, max) : s;
        }

        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }

        public String getEmotion() { return emotion; }
        public void setEmotion(String emotion) { this.emotion = truncate(emotion, MAX_EMOTION); }

        public Double getEmotionConfidence() { return emotionConfidence; }
        public void setEmotionConfidence(Double emotionConfidence) { this.emotionConfidence = emotionConfidence; }

        public String getSentiment() { return sentiment; }
        public void setSentiment(String sentiment) { this.sentiment = truncate(sentiment, MAX_SENTIMENT); }

        public Double getSentimentConfidence() { return sentimentConfidence; }
        public void setSentimentConfidence(Double sentimentConfidence) { this.sentimentConfidence = sentimentConfidence; }

        public String getEmotionalThemes() { return emotionalThemes; }
        public void setEmotionalThemes(String emotionalThemes) { this.emotionalThemes = truncate(emotionalThemes, MAX_THEMES); }

        public String getSummary() { return summary; }
        public void setSummary(String summary) { this.summary = truncate(summary, MAX_SUMMARY); }

        public String getReflectionPrompt() { return reflectionPrompt; }
        public void setReflectionPrompt(String reflectionPrompt) { this.reflectionPrompt = truncate(reflectionPrompt, MAX_REFLECTION); }

        public String getAnalysisVersion() { return analysisVersion; }
        public void setAnalysisVersion(String analysisVersion) { this.analysisVersion = analysisVersion; }

        public Integer getAnalyzedContentVersion() { return analyzedContentVersion; }
        public void setAnalyzedContentVersion(Integer analyzedContentVersion) { this.analyzedContentVersion = analyzedContentVersion; }

        public Instant getAnalyzedAt() { return analyzedAt; }
        public void setAnalyzedAt(Instant analyzedAt) { this.analyzedAt = analyzedAt; }
    }
}
