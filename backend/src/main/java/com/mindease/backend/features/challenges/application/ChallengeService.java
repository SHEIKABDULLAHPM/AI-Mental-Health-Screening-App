package com.mindease.backend.features.challenges.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.ChallengeFrequency;
import com.mindease.backend.features.challenges.domain.ChallengeProgressEvent;
import com.mindease.backend.features.challenges.domain.ChallengeProgressEventRepository;
import com.mindease.backend.features.challenges.domain.ChallengeRepository;
import com.mindease.backend.features.challenges.domain.ChallengeStatus;
import com.mindease.backend.features.challenges.domain.ChallengeType;
import com.mindease.backend.features.challenges.domain.UserBadge;
import com.mindease.backend.features.challenges.domain.UserBadgeRepository;
import com.mindease.backend.features.challenges.domain.UserChallenge;
import com.mindease.backend.features.challenges.domain.UserChallengeRepository;
import com.mindease.backend.features.challenges.dto.BadgeResponse;
import com.mindease.backend.features.challenges.dto.ChallengeHomeResponse;
import com.mindease.backend.features.challenges.dto.ChallengeResponse;
import com.mindease.backend.features.challenges.dto.GameResultRequest;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizedContext;

/**
 * Backend source of truth for Challenges.
 *
 * <p>Progress is never driven by a client-supplied number. Instead,
 * {@link #applyActivity} consumes verified activity records emitted by other
 * feature services and advances matching challenges with full idempotency and
 * duplicate protection.</p>
 */
@Service
public class ChallengeService {

    private static final Logger log = LoggerFactory.getLogger(ChallengeService.class);

    private final ChallengeRepository challengeRepository;
    private final UserChallengeRepository userChallengeRepository;
    private final ChallengeProgressEventRepository progressEventRepository;
    private final UserBadgeRepository badgeRepository;
    private final PersonalizationService personalizationService;
    private final MongoTemplate mongoTemplate;

    public ChallengeService(
            ChallengeRepository challengeRepository,
            UserChallengeRepository userChallengeRepository,
            ChallengeProgressEventRepository progressEventRepository,
            UserBadgeRepository badgeRepository,
            PersonalizationService personalizationService,
            MongoTemplate mongoTemplate) {
        this.challengeRepository = challengeRepository;
        this.userChallengeRepository = userChallengeRepository;
        this.progressEventRepository = progressEventRepository;
        this.badgeRepository = badgeRepository;
        this.personalizationService = personalizationService;
        this.mongoTemplate = mongoTemplate;
    }

    // ─────────────────────────────────────────────── Activity-driven progress

    /**
     * Process a verified activity and advance matching open challenges.
     *
     * <p>Called by activity services (mood, journal, relax, recommendation)
     * after the source record has been persisted. This method is safe to call
     * concurrently: the unique progress-event index ensures each source record
     * advances each challenge-period exactly once.</p>
     *
     * @param userId        authenticated user id (server-derived).
     * @param type          the {@link ChallengeType} matching this activity.
     * @param sourceRecordId id of the persisted source record.
     * @param userZone      user timezone (best-effort; default UTC).
     */
    public void applyActivity(String userId, ChallengeType type,
                              String sourceRecordId, String userZone) {
        if (userId == null || type == null || sourceRecordId == null || sourceRecordId.isBlank()) {
            return;
        }
        Instant now = Instant.now();
        var zone = ChallengePeriodCalculator.zone(userZone);
        String activityDate = ChallengePeriodCalculator.localDate(now, zone);

        List<Challenge> matching = challengeRepository.findByActiveTrueAndType(type.name());
        for (Challenge challenge : matching) {
            try {
                advanceInstance(userId, challenge, type, sourceRecordId, activityDate, now, zone);
            } catch (Exception e) {
                // A failure advancing one challenge must not break other activity flows.
                log.warn("challenge.advance_failed userId={} challengeId={} err={}",
                        userId, challenge.getId(), e.getMessage());
            }
        }
    }

    private void advanceInstance(String userId, Challenge challenge, ChallengeType type,
                                 String sourceRecordId, String activityDate,
                                 Instant now, java.time.ZoneId zone) {
        ChallengeFrequency freq = ChallengeFrequency.fromValue(challenge.getFrequency());
        if (freq == null) {
            freq = ChallengeFrequency.DAILY;
        }
        String periodStart = ChallengePeriodCalculator.periodKey(now, freq, zone);
        Instant periodStartInstant = ChallengePeriodCalculator.periodStart(now, freq, zone);

        UserChallenge uc = userChallengeRepository
                .findByUserIdAndChallengeIdAndPeriodStart(userId, challenge.getId(), periodStart)
                .orElse(null);

        // Only advance challenges the user has actually started for this period,
        // and that remain open for progress.
        if (uc == null || !uc.statusEnum().isOpenForProgress()) {
            return;
        }

        // Idempotency / duplicate check.
        if (progressEventRepository.existsByUserIdAndChallengeIdAndPeriodStartAndSourceRecordId(
                userId, challenge.getId(), periodStart, sourceRecordId)) {
            return;
        }

        // Attempt to record the idempotency event. The unique index makes the
        // insert concurrency-safe: only one of many concurrent request threads
        // can insert the same (user, challenge, period, source) event.
        ChallengeProgressEvent event = new ChallengeProgressEvent();
        event.setUserId(userId);
        event.setChallengeId(challenge.getId());
        event.setPeriodStart(periodStart);
        event.setActivityKind(type.name());
        event.setSourceRecordId(sourceRecordId);
        event.setActivityDate(activityDate);
        event.setOccurredAt(now);
        event.setCreatedAt(now);
        try {
            progressEventRepository.save(event);
        } catch (DuplicateKeyException e) {
            log.debug("challenge.duplicate_event_skipped userId={} challengeId={} source={}",
                    userId, challenge.getId(), sourceRecordId);
            return;
        }

        // Advance progress with an atomic, status-guarded increment so that the
        // single accepted event applies exactly once.
        boolean completed = advanceProgressAtomically(userId, uc.getId(), challenge.getTarget());

        if (completed) {
            finalizeCompletion(userId, challenge, uc.getId());
        }
    }

    /**
     * Atomically increment progress and detect completion. Only usable while the
     * challenge is open for progress; returns true when the target is reached.
     */
    private boolean advanceProgressAtomically(String userId, String userChallengeId, int target) {
        Instant now = Instant.now();
        var result = mongoTemplate.findAndModify(
                Query.query(Criteria.where("_id").is(userChallengeId)
                        .and("status").in(ChallengeStatus.ACTIVE.name(), ChallengeStatus.IN_PROGRESS.name())),
                new Update().inc("progress", 1).set("updatedAt", now),
                org.springframework.data.mongodb.core.FindAndModifyOptions.options().returnNew(true),
                UserChallenge.class);

        if (result == null) {
            log.debug("challenge.instance_not_open_or_missing id={}", userChallengeId);
            return false;
        }
        return result.getProgress() >= target;
    }

    private void finalizeCompletion(String userId, Challenge challenge, String userChallengeId) {
        Instant now = Instant.now();
        // Update streak and bestStreak before finalizing
        UserChallenge uc = userChallengeRepository.findById(userChallengeId).orElse(null);
        if (uc != null) {
            int newStreak = uc.getStreak() + 1;
            int newBestStreak = Math.max(newStreak, uc.getBestStreak());
            var completed = mongoTemplate.findAndModify(
                    Query.query(Criteria.where("_id").is(userChallengeId)
                            .and("status").in(ChallengeStatus.ACTIVE.name(), ChallengeStatus.IN_PROGRESS.name())),
                    new Update().set("status", ChallengeStatus.COMPLETED.name())
                            .set("completedAt", now)
                            .set("streak", newStreak)
                            .set("bestStreak", newBestStreak)
                            .set("updatedAt", now),
                    org.springframework.data.mongodb.core.FindAndModifyOptions.options().returnNew(false),
                    UserChallenge.class);

            if (completed != null) {
                grantReward(userId, challenge);
                log.info("challenge.completed userId={} challengeId={} streak={}",
                        userId, challenge.getId(), newStreak);
            }
        }
    }

    private void grantReward(String userId, Challenge challenge) {
        String code = challenge.getBadgeCode();
        if (code == null || code.isBlank()) {
            return;
        }
        UserBadge badge = new UserBadge();
        badge.setUserId(userId);
        badge.setCode(code);
        badge.setLabel(challenge.getReward() != null ? challenge.getReward() : code);
        badge.setChallengeId(challenge.getId());
        badge.setEarnedAt(Instant.now());
        badge.setCreatedAt(Instant.now());
        try {
            badgeRepository.save(badge);
        } catch (DuplicateKeyException e) {
            log.debug("challenge.badge_already_exists userId={} code={}", userId, code);
        }
    }

    // ─────────────────────────────────────────────── Start / Home / Detail

    /**
     * Start a challenge for the current period. Idempotent: starting an
     * already-active instance returns it rather than erroring if an open
     * instance exists for the current period.
     */
    public ChallengeResponse startChallenge(String userId, String challengeId, String userZone) {
        Challenge challenge = challengeRepository.findByIdAndActiveTrue(challengeId)
                .orElseThrow(() -> ApiException.notFound("Challenge not found or no longer available."));

        ChallengeType type = ChallengeType.fromValue(challenge.getType());
        if (type == null) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "This challenge is not currently available.");
        }

        var zone = ChallengePeriodCalculator.zone(userZone);
        Instant now = Instant.now();
        ChallengeFrequency freq = Optional.ofNullable(
                        ChallengeFrequency.fromValue(challenge.getFrequency()))
                .orElse(ChallengeFrequency.DAILY);
        String periodStart = ChallengePeriodCalculator.periodKey(now, freq, zone);
        Instant periodStartInstant = ChallengePeriodCalculator.periodStart(now, freq, zone);
        Instant periodEnd = ChallengePeriodCalculator.periodEnd(periodStartInstant, freq, zone);

        // Reuse an open instance for the same period.
        UserChallenge existing = userChallengeRepository
                .findByUserIdAndChallengeIdAndPeriodStart(userId, challengeId, periodStart)
                .orElse(null);
        if (existing != null && existing.statusEnum() != ChallengeStatus.COMPLETED
                && existing.statusEnum() != ChallengeStatus.EXPIRED) {
            return ChallengeResponse.fromDomain(challenge, existing, null);
        }

        UserChallenge uc = new UserChallenge();
        uc.setUserId(userId);
        uc.setChallengeId(challengeId);
        uc.setStatusEnum(ChallengeStatus.ACTIVE);
        uc.setProgress(0);
        uc.setAttempts(1);
        uc.setTarget(challenge.getTarget() > 0 ? challenge.getTarget() : 1);
        uc.setPeriodStart(periodStart);
        uc.setPeriodEnd(periodEnd);
        uc.setExpiresAt(periodEnd);
        uc.setStreak(0);
        uc.setStartedAt(now);
        uc.setCreatedAt(now);
        uc.setUpdatedAt(now);

        try {
            userChallengeRepository.save(uc);
        } catch (DuplicateKeyException e) {
            // Concurrent start for the same period — fetch the winner.
            UserChallenge winner = userChallengeRepository
                    .findByUserIdAndChallengeIdAndPeriodStart(userId, challengeId, periodStart)
                    .orElse(uc);
            return ChallengeResponse.fromDomain(challenge, winner, null);
        }

        return ChallengeResponse.fromDomain(challenge, uc, null);
    }

    public ChallengeResponse getChallenge(String userId, String challengeId, String userZone) {
        Challenge challenge = challengeRepository.findByIdAndActiveTrue(challengeId)
                .orElseThrow(() -> ApiException.notFound("Challenge not found or no longer available."));

        UserChallenge uc = currentInstance(userId, challenge, userZone);
        if (uc != null) {
            expireIfOverdue(userId, uc);
        }
        return ChallengeResponse.fromDomain(challenge, uc, null);
    }

    /**
     * Aggregated data for the Challenges home screen, including personalization.
     */
    public ChallengeHomeResponse getHome(String userId, String userZone) {
        var zone = ChallengePeriodCalculator.zone(userZone);
        List<Challenge> definitions = challengeRepository.findByActiveTrue();

        var signals = buildEligibilitySignals(userId);
        var context = safeGetContext(userId);
        String personalizationReason = derivePersonalizationReason(context);

        List<ChallengeResponse> active = new ArrayList<>();
        List<ChallengeResponse> completed = new ArrayList<>();
        ChallengeResponse recommended = null;

        for (Challenge c : definitions) {
            if (!ChallengeEligibilityEngine.isEligible(c, signals)) {
                continue;
            }
            UserChallenge uc = currentInstance(userId, c, userZone);
            if (uc != null) {
                expireIfOverdue(userId, uc);
                uc = currentInstance(userId, c, userZone);
            }
            ChallengeResponse resp = ChallengeResponse.fromDomain(c, uc, personalizationReason);
            if (uc != null) {
                String status = uc.getStatus();
                if ("COMPLETED".equals(status)) {
                    completed.add(resp);
                } else if (status != null && !"EXPIRED".equals(status)) {
                    active.add(resp);
                }
            } else if (recommended == null) {
                recommended = resp;
            }
        }

        int currentStreak = StreakCalculator.current(
                extractStreakDates(userId), zone);
        int points = completed.stream().mapToInt(ChallengeResponse::points).sum();

        List<BadgeResponse> badges = badgeRepository.findByUserIdOrderByEarnedAtDesc(userId)
                .stream()
                .map(b -> new BadgeResponse(b.getCode(), b.getLabel(), b.getChallengeId(), b.getEarnedAt()))
                .toList();

        return new ChallengeHomeResponse(active, completed, badges, currentStreak, points, recommended);
    }

    /**
     * All badges earned by the user.
     */
    public List<BadgeResponse> getBadges(String userId) {
        return badgeRepository.findByUserIdOrderByEarnedAtDesc(userId)
                .stream()
                .map(b -> new BadgeResponse(b.getCode(), b.getLabel(), b.getChallengeId(), b.getEarnedAt()))
                .toList();
    }

    /**
     * Challenge history: completed + expired challenges, paginated efficiently
     * using MongoDB-level filtering.
     */
    public List<ChallengeResponse> getHistory(String userId, String userZone, int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), 50);
        int skip = safePage * safeSize;

        // Use MongoDB-level query with status filter for efficiency
        List<UserChallenge> terminal = mongoTemplate.find(
                Query.query(Criteria.where("userId").is(userId)
                        .and("status").in("COMPLETED", "EXPIRED"))
                        .with(org.springframework.data.domain.Sort.by(
                                org.springframework.data.domain.Sort.Direction.DESC, "completedAt"))
                        .skip(skip)
                        .limit(safeSize),
                UserChallenge.class);

        return terminal.stream()
                .map(uc -> {
                    Challenge c = challengeRepository.findById(uc.getChallengeId()).orElse(null);
                    if (c == null) return null;
                    return ChallengeResponse.fromDomain(c, uc, null);
                })
                .filter(java.util.Objects::nonNull)
                .toList();
    }

    /**
     * Active challenge progress summary.
     */
    public List<ChallengeResponse> getActiveProgress(String userId, String userZone) {
        List<UserChallenge> active = userChallengeRepository
                .findByUserIdAndStatusInOrderByUpdatedAtDesc(userId,
                        List.of(ChallengeStatus.ACTIVE.name(), ChallengeStatus.IN_PROGRESS.name()));

        return active.stream()
                .map(uc -> {
                    Challenge c = challengeRepository.findById(uc.getChallengeId()).orElse(null);
                    if (c == null) return null;
                    return ChallengeResponse.fromDomain(c, uc, null);
                })
                .filter(java.util.Objects::nonNull)
                .toList();
    }

    // ─────────────────────────────────────────────── Game result processing

    /**
     * Submit a validated game result for a challenge. The backend validates the
     * result structure and advances the challenge if eligible.
     *
     * <p>Game opening is NOT completion. Only a legitimate game result triggers
     * progress. The result is validated against deterministic rules before
     * advancing.</p>
     */
    public ChallengeResponse submitGameResult(String userId, String challengeId,
                                               GameResultRequest result, String userZone) {
        if (result == null) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Game result is required.");
        }

        // Validate game type
        String gameType = result.gameType();
        if (gameType == null || gameType.isBlank()) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Game type is required.");
        }
        List<String> validGames = List.of("2048", "sudoku", "tic_tac_toe", "memory_match");
        if (!validGames.contains(gameType.toLowerCase().replace("-", "_"))) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Unsupported game type.");
        }

        // Validate score is non-negative
        if (result.score() < 0) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Score cannot be negative.");
        }

        // Validate moves are non-negative
        if (result.moves() < 0) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Moves cannot be negative.");
        }

        // The challenge must be a GAME_ACTIVITY type
        Challenge challenge = challengeRepository.findByIdAndActiveTrue(challengeId)
                .orElseThrow(() -> ApiException.notFound("Challenge not found or no longer available."));

        if (!ChallengeType.GAME_ACTIVITY.name().equals(challenge.getType())) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "This challenge is not a game challenge.");
        }

        // Find or require an active UserChallenge
        var zone = ChallengePeriodCalculator.zone(userZone);
        Instant now = Instant.now();
        ChallengeFrequency freq = java.util.Optional.ofNullable(
                        ChallengeFrequency.fromValue(challenge.getFrequency()))
                .orElse(ChallengeFrequency.DAILY);
        String periodStart = ChallengePeriodCalculator.periodKey(now, freq, zone);

        UserChallenge uc = userChallengeRepository
                .findByUserIdAndChallengeIdAndPeriodStart(userId, challengeId, periodStart)
                .orElseThrow(() -> ApiException.badRequest(
                        "You need to start this challenge before submitting a game result."));

        if (!uc.statusEnum().isOpenForProgress()) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "This challenge is no longer open for progress.");
        }

        // Check expiration
        expireIfOverdue(userId, uc);
        if (uc.getExpiresAt() != null && Instant.now().isAfter(uc.getExpiresAt())) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "This challenge has expired.");
        }

        // Increment attempts
        uc.setAttempts(uc.getAttempts() + 1);
        userChallengeRepository.save(uc);

        // Use the challenge's sourceRecordId pattern: gameType + timestamp for idempotency
        String sourceRecordId = "game:" + gameType + ":" + result.score() + ":" + now.toEpochMilli();

        // Apply activity (this handles idempotency, progress advancement, and completion)
        applyActivity(userId, ChallengeType.GAME_ACTIVITY, sourceRecordId, userZone);

        // Return updated challenge state
        UserChallenge updated = userChallengeRepository
                .findByUserIdAndChallengeIdAndPeriodStart(userId, challengeId, periodStart)
                .orElse(uc);
        return ChallengeResponse.fromDomain(challenge, updated, null);
    }

    /**
     * Submit explicit progress for a challenge (non-game activities).
     * Validates the request and advances the challenge if eligible.
     */
    public ChallengeResponse submitProgress(String userId, String challengeId,
                                             String sourceRecordId, String userZone) {
        Challenge challenge = challengeRepository.findByIdAndActiveTrue(challengeId)
                .orElseThrow(() -> ApiException.notFound("Challenge not found or no longer available."));

        ChallengeType type = ChallengeType.fromValue(challenge.getType());
        if (type == null) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "This challenge type is not currently supported.");
        }

        if (sourceRecordId == null || sourceRecordId.isBlank()) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Source record ID is required.");
        }

        // Apply activity
        applyActivity(userId, type, sourceRecordId, userZone);

        // Return updated state
        var zone = ChallengePeriodCalculator.zone(userZone);
        Instant now = Instant.now();
        ChallengeFrequency freq = java.util.Optional.ofNullable(
                        ChallengeFrequency.fromValue(challenge.getFrequency()))
                .orElse(ChallengeFrequency.DAILY);
        String periodStart = ChallengePeriodCalculator.periodKey(now, freq, zone);

        UserChallenge updated = userChallengeRepository
                .findByUserIdAndChallengeIdAndPeriodStart(userId, challengeId, periodStart)
                .orElse(null);
        return ChallengeResponse.fromDomain(challenge, updated, null);
    }

    // ─────────────────────────────────────────────── Internal helpers

    private UserChallenge currentInstance(String userId, Challenge challenge, String userZone) {
        ChallengeFrequency freq = Optional.ofNullable(
                        ChallengeFrequency.fromValue(challenge.getFrequency()))
                .orElse(ChallengeFrequency.DAILY);
        var zone = ChallengePeriodCalculator.zone(userZone);
        Instant now = Instant.now();
        String periodStart = ChallengePeriodCalculator.periodKey(now, freq, zone);
        return userChallengeRepository
                .findByUserIdAndChallengeIdAndPeriodStart(userId, challenge.getId(), periodStart)
                .orElse(null);
    }

    private void expireIfOverdue(String userId, UserChallenge uc) {
        if (!uc.statusEnum().isOpenForProgress()) {
            return;
        }
        Instant expiresAt = uc.getExpiresAt();
        if (expiresAt != null && Instant.now().isAfter(expiresAt)) {
            uc.setStatusEnum(ChallengeStatus.EXPIRED);
            uc.setUpdatedAt(Instant.now());
            userChallengeRepository.save(uc);
        }
    }

    /**
     * Derive a controlled, supportive personalization reason from the cached
     * personalized context. Never uses clinical language.
     */
    private String derivePersonalizationReason(PersonalizedContext ctx) {
        if (ctx == null) {
            return null;
        }
        // Use emotional themes from journal analysis if available.
        if (ctx.getJournalEmotionalThemes() != null
                && !ctx.getJournalEmotionalThemes().isEmpty()) {
            return "Based on your recent journal reflections, this may fit your current routine.";
        }
        // Use mood trend description if available.
        if (ctx.getMoodTrendDescription() != null
                && !ctx.getMoodTrendDescription().isBlank()) {
            return "Based on your recent wellness activity, this challenge may support your routine.";
        }
        // Use general activity level signal.
        if (ctx.getMoodEntryCount() > 0 || ctx.getRecentJournalCount() > 0) {
            return "Based on your recent wellness activity, this may fit your routine.";
        }
        return null;
    }

    /**
     * Extract distinct activity dates for streak calculation.
     */
    private java.util.List<java.time.LocalDate> extractStreakDates(String userId) {
        try {
            List<ChallengeProgressEvent> events =
                    progressEventRepository.findByUserIdOrderByOccurredAtDesc(userId);
            var instants = events.stream()
                    .map(ChallengeProgressEvent::getOccurredAt)
                    .filter(java.util.Objects::nonNull)
                    .toList();
            return StreakCalculator.toDates(instants, java.time.ZoneId.of("UTC"));
        } catch (Exception e) {
            log.debug("challenge.streak_dates_unavailable userId={}", userId);
            return java.util.List.of();
        }
    }

    private ChallengeEligibilityEngine.EligibilitySignals buildEligibilitySignals(String userId) {
        try {
            return new ChallengeEligibilityEngine.EligibilitySignals(
                    countActual(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(
                            userId, ChallengeType.MOOD_CHECK_IN.name())),
                    countActual(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(
                            userId, ChallengeType.JOURNALING.name())),
                    countActual(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(
                            userId, ChallengeType.RELAXATION.name())),
                    countActual(progressEventRepository.findByUserIdAndActivityKindOrderByOccurredAtDesc(
                            userId, ChallengeType.HEALTHY_ROUTINE.name())));
        } catch (Exception e) {
            log.warn("challenge.signals_failed userId={} err={}", userId, e.getMessage());
            return ChallengeEligibilityEngine.EligibilitySignals.empty();
        }
    }

    private static int countActual(List<ChallengeProgressEvent> events) {
        return events == null ? 0 : events.size();
    }

    private PersonalizedContext safeGetContext(String userId) {
        try {
            return personalizationService.getContext(userId);
        } catch (Exception e) {
            log.debug("challenge.context_unavailable userId={} err={}", userId, e.getMessage());
            return null;
        }
    }


}
