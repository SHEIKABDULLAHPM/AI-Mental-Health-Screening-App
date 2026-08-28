package com.mindease.backend.coach.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "coach_conversations")
@CompoundIndex(name = "userId_updatedAt_idx", def = "{'userId': 1, 'updatedAt': -1}")
public class Conversation {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String title;

    private int messageCount;

    private String lastMessagePreview;

    private String safetyState; // NORMAL, CONCERNING, HIGH_RISK, IMMEDIATE_DANGER

    @Version
    private Long documentVersion;

    private Instant createdAt;
    private Instant updatedAt;

    public Conversation() {
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public int getMessageCount() { return messageCount; }
    public void setMessageCount(int messageCount) { this.messageCount = messageCount; }

    public String getLastMessagePreview() { return lastMessagePreview; }
    public void setLastMessagePreview(String lastMessagePreview) {
        this.lastMessagePreview = lastMessagePreview != null && lastMessagePreview.length() > 200
                ? lastMessagePreview.substring(0, 200) : lastMessagePreview;
    }

    public String getSafetyState() { return safetyState; }
    public void setSafetyState(String safetyState) { this.safetyState = safetyState; }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
