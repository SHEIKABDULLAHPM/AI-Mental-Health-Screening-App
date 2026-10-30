package com.mindease.backend.features.challenges.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A user's progress on a single instance of a Challenge.
 *
 * <p>Progress is always derived from verified activity server-side. Status is a
 * server-controlled state machine (see {@link ChallengeStatus}).</p>
 *
 * <p>For periodic challenges the same challengeId repeats over time; each
 * instance is identified by (userId, challengeId, periodStart) so that daily and
 * weekly periods are distinct and never merged.</p>
 */
@Document(collection = "user_challenges")
@CompoundIndexes({
    @CompoundIndex(name = "user_status_idx", def = "{'userId': 1, 'status': 1}"),
    @CompoundIndex(name = "user_challenge_period_idx",
            def = "{'userId': 1, 'challengeId': 1, 'periodStart': 1}", unique = true),
    @CompoundIndex(name = "user_created_idx", def = "{'userId': 1, 'createdAt': -1}"),
    @CompoundIndex(name = "user_expiry_idx", def = "{'userId': 1, 'expiresAt': 1}")
})
public class UserChallenge {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String challengeId;

    /** Challenge lifecycle state. See {@link ChallengeStatus}. */
    private String status;

    /** Verified progress within the current period. */
    private int progress;

    /** Target for the current period. */
    private int target;

    /** ISO-8601 start of the current period (local day or local ISO week). */
    private String periodStart;

    /** End of the current period (exclusive). */
    private Instant periodEnd;

    /** When the current period expires (for non-daily long running challenges). */
    private Instant expiresAt;

    /** Number of start/attempts for this challenge instance. */
    private int attempts;

    /** Latest day (ISO date local) on which a verified activity contributed. */
    private String lastActivityDate;

    /** Running streak of consecutive active days. */
    private int streak;

    /** Best (longest) streak ever achieved on this challenge. */
    private int bestStreak;

    private Instant startedAt;
    private Instant completedAt;
    private Instant createdAt;
    private Instant updatedAt;

    public UserChallenge() {
    }

    // ── Helpers ─────────────────────────────────────────────────────

    public ChallengeStatus statusEnum() {
        return ChallengeStatus.fromValue(status);
    }

    public void setStatusEnum(ChallengeStatus status) {
        this.status = status.name();
    }

    public Instant currentPeriodStartInstant() {
        return periodStart == null ? null : Instant.parse(periodStart);
    }

    // ── Getters / Setters ───────────────────────────────────────────

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getChallengeId() { return challengeId; }
    public void setChallengeId(String challengeId) { this.challengeId = challengeId; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public int getProgress() { return progress; }
    public void setProgress(int progress) { this.progress = progress; }

    public int getTarget() { return target; }
    public void setTarget(int target) { this.target = target; }

    public String getPeriodStart() { return periodStart; }
    public void setPeriodStart(String periodStart) { this.periodStart = periodStart; }

    public Instant getPeriodEnd() { return periodEnd; }
    public void setPeriodEnd(Instant periodEnd) { this.periodEnd = periodEnd; }

    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }

    public String getLastActivityDate() { return lastActivityDate; }
    public void setLastActivityDate(String lastActivityDate) { this.lastActivityDate = lastActivityDate; }

    public int getAttempts() { return attempts; }
    public void setAttempts(int attempts) { this.attempts = attempts; }

    public int getStreak() { return streak; }
    public void setStreak(int streak) { this.streak = streak; }

    public int getBestStreak() { return bestStreak; }
    public void setBestStreak(int bestStreak) { this.bestStreak = bestStreak; }

    public Instant getStartedAt() { return startedAt; }
    public void setStartedAt(Instant startedAt) { this.startedAt = startedAt; }

    public Instant getCompletedAt() { return completedAt; }
    public void setCompletedAt(Instant completedAt) { this.completedAt = completedAt; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
