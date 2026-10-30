package com.mindease.backend.features.challenges.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A badge earned by a user. Earning is deterministic and idempotent: a user can
 * only ever hold one instance of a given badge (unique user+code), so concurrent
 * completion cannot create duplicate badges.
 */
@Document(collection = "user_badges")
@CompoundIndex(name = "user_badge_uniq", def = "{'userId': 1, 'code': 1}", unique = true)
public class UserBadge {

    @Id
    private String id;

    @Indexed
    private String userId;

    /** Deterministic badge code, e.g. "MOOD_CONSISTENCY_5". */
    private String code;

    private String label;

    /** The challengeId whose completion unlocked this badge (if any). */
    private String challengeId;

    private Instant earnedAt;
    private Instant createdAt;

    public UserBadge() {
    }

    // ── Getters / Setters ───────────────────────────────────────────

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }

    public String getLabel() { return label; }
    public void setLabel(String label) { this.label = label; }

    public String getChallengeId() { return challengeId; }
    public void setChallengeId(String challengeId) { this.challengeId = challengeId; }

    public Instant getEarnedAt() { return earnedAt; }
    public void setEarnedAt(Instant earnedAt) { this.earnedAt = earnedAt; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
}
