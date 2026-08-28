package com.mindease.backend.personalization.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Tracks cross-feature personalization feedback events.
 * Used to build the feedback loop: feature interaction → context update → future personalization.
 *
 * <p>Stores only the signal type and source, never raw private content.</p>
 */
@Document(collection = "personalization_feedback")
@CompoundIndex(name = "userId_type_createdAt_idx", def = "{'userId': 1, 'eventType': 1, 'createdAt': -1}")
@CompoundIndex(name = "userId_createdAt_idx", def = "{'userId': 1, 'createdAt': -1}")
public class PersonalizationFeedback {

    @Id
    private String id;

    @Indexed
    private String userId;

    /**
     * Type of feedback event:
     * RECOMMENDATION_COMPLETED, RECOMMENDATION_DISMISSED, RECOMMENDATION_HELPFUL,
     * RECOMMENDATION_NOT_USEFUL, MOOD_RECORDED, JOURNAL_CREATED, COACH_INTERACTION,
     * ACTIVITY_COMPLETED, PREFERENCE_EXPRESSED
     */
    private String eventType;

    /** Optional: the content ID this feedback is about. */
    private String contentId;

    /** Optional: the feature that generated this event. */
    private String sourceFeature;

    /** Optional: additional structured metadata (JSON-safe). */
    private java.util.Map<String, String> metadata;

    /** Relevance weight for this feedback (0.0 – 1.0). */
    private double weight;

    @Version
    private Long documentVersion;

    private Instant createdAt;

    public PersonalizationFeedback() {}

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }

    public String getContentId() { return contentId; }
    public void setContentId(String contentId) { this.contentId = contentId; }

    public String getSourceFeature() { return sourceFeature; }
    public void setSourceFeature(String sourceFeature) { this.sourceFeature = sourceFeature; }

    public java.util.Map<String, String> getMetadata() { return metadata; }
    public void setMetadata(java.util.Map<String, String> metadata) { this.metadata = metadata; }

    public double getWeight() { return weight; }
    public void setWeight(double weight) { this.weight = weight; }

    public Long getDocumentVersion() { return documentVersion; }
    public void setDocumentVersion(Long documentVersion) { this.documentVersion = documentVersion; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}
