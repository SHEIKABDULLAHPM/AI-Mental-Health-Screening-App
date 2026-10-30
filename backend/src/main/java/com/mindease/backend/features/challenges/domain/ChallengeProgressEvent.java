package com.mindease.backend.features.challenges.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Records that a specific source activity has already contributed to a specific
 * challenge instance. Used for idempotency and duplicate protection.
 *
 * <p>The natural uniqueness is (userId, challengeId, periodStart, sourceType,
 * sourceRecordId): the same source record cannot advance the same challenge
 * instance twice, even under concurrent requests.</p>
 */
@Document(collection = "challenge_progress_events")
@CompoundIndexes({
    @CompoundIndex(name = "uc_source_uniq",
            def = "{'userId': 1, 'challengeId': 1, 'periodStart': 1, 'sourceType': 1, 'sourceRecordId': 1}",
            unique = true),
    @CompoundIndex(name = "user_kind_idx", def = "{'userId': 1, 'activityKind': 1, 'occurredAt': -1}"),
    @CompoundIndex(name = "user_challenge_idx", def = "{'userId': 1, 'challengeId': 1, 'periodStart': 1}")
})
public class ChallengeProgressEvent {

    @Id
    private String id;

    private String userId;

    private String challengeId;

    private String periodStart;

    /** Activity kind, e.g. MOOD_CHECK_IN, JOURNALING, RELAXATION, HEALTHY_ROUTINE. */
    private String activityKind;

    /** The id of the source record (mood/journal/relax/recommendation id). */
    private String sourceRecordId;

    /** ISO date (local) of the activity. */
    private String activityDate;

    private Instant occurredAt;
    private Instant createdAt;

    public ChallengeProgressEvent() {
    }

    // ── Getters / Setters ───────────────────────────────────────────

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getChallengeId() { return challengeId; }
    public void setChallengeId(String challengeId) { this.challengeId = challengeId; }

    public String getPeriodStart() { return periodStart; }
    public void setPeriodStart(String periodStart) { this.periodStart = periodStart; }

    public String getActivityKind() { return activityKind; }
    public void setActivityKind(String activityKind) { this.activityKind = activityKind; }

    public String getSourceRecordId() { return sourceRecordId; }
    public void setSourceRecordId(String sourceRecordId) { this.sourceRecordId = sourceRecordId; }

    public String getActivityDate() { return activityDate; }
    public void setActivityDate(String activityDate) { this.activityDate = activityDate; }

    public Instant getOccurredAt() { return occurredAt; }
    public void setOccurredAt(Instant occurredAt) { this.occurredAt = occurredAt; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}
