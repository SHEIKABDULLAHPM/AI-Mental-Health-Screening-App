package com.mindease.backend.features.challenges.application;

import java.time.Instant;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.ChallengeFrequency;
import com.mindease.backend.features.challenges.domain.ChallengeRepository;
import com.mindease.backend.features.challenges.domain.ChallengeType;

/**
 * Seeds the controlled challenge catalog on first startup.
 *
 * <p>Every challenge here is backed by a real, verifiable activity source and is
 * defined explicitly — never by an LLM. Frequency is DAILY (one verified
 * activity per day) or WEEKLY (N activities per week).</p>
 */
@Component
public class ChallengeSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(ChallengeSeeder.class);

    private final ChallengeRepository repository;

    public ChallengeSeeder(ChallengeRepository repository) {
        this.repository = repository;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (repository.count() > 0) {
            log.info("Challenges already present, skipping seed.");
            return;
        }

        Instant now = Instant.now();
        List<Challenge> challenges = List.of(
                // ── Mood ──────────────────────────────────────────
                seedChallenge(
                        "Today's Mood Check-In",
                        "Take one calm moment to check in with how you are feeling today.",
                        "Regular check-ins can help you notice patterns in how your mood shifts over time.",
                        ChallengeType.MOOD_CHECK_IN, ChallengeFrequency.DAILY, 1,
                        10, "Mood Check-In", "MOOD_CHECK_IN_1", "mood:any",
                        "Daily Wellness", "easy", "2 min", now),
                seedChallenge(
                        "5-Day Mood Awareness",
                        "Notice and record your mood on 5 days this week.",
                        "Building awareness of your feelings is a kind, low-pressure way to support yourself.",
                        ChallengeType.MOOD_CHECK_IN, ChallengeFrequency.WEEKLY, 5,
                        50, "Mood Consistency Badge", "MOOD_CONSISTENCY_5", "mood:any",
                        "Daily Wellness", "easy", "2 min", now),
                // ── Journal ────────────────────────────────────────
                seedChallenge(
                        "Today's Journal Reflection",
                        "Write a short reflection about your day.",
                        "Journaling can help you organise thoughts and make space for self-reflection.",
                        ChallengeType.JOURNALING, ChallengeFrequency.DAILY, 1,
                        10, "Journal Reflection", "JOURNAL_REFLECTION_1", "journal:any",
                        "Reflection", "easy", "5 min", now),
                seedChallenge(
                        "3 Journal Entries This Week",
                        "Create three journal entries over the week, at your own pace.",
                        "A gentle rhythm of journaling can support clear thinking and emotional awareness.",
                        ChallengeType.JOURNALING, ChallengeFrequency.WEEKLY, 3,
                        40, "Journal Persistence Badge", "JOURNAL_PERSISTENCE_3", "journal:any",
                        "Reflection", "medium", "5 min", now),
                // ── Relaxation ─────────────────────────────────────
                seedChallenge(
                        "Daily Relaxation Moment",
                        "Complete one relaxation or breathing activity today.",
                        "Short relaxation breaks can help lower tension and bring gentle calm.",
                        ChallengeType.RELAXATION, ChallengeFrequency.DAILY, 1,
                        10, "Relaxation Moment", "RELAX_DAILY_1", "relax:active",
                        "Relaxation", "easy", "5 min", now),
                seedChallenge(
                        "4 Relaxation Sessions This Week",
                        "Complete four relaxation sessions across the week.",
                        "Returning to relaxation regularly can deepen a sense of ease over time.",
                        ChallengeType.RELAXATION, ChallengeFrequency.WEEKLY, 4,
                        50, "Relaxation Steady Badge", "RELAX_STEADY_4", "relax:active",
                        "Relaxation", "medium", "5 min", now),
                // ── Wellness ───────────────────────────────────────
                seedChallenge(
                        "Try One Wellness Activity",
                        "Complete a recommended wellness activity that fits your current routine.",
                        "Following through on a suggested activity can help you feel a sense of progress.",
                        ChallengeType.HEALTHY_ROUTINE, ChallengeFrequency.WEEKLY, 1,
                        20, "First Step Badge", "HEALTHY_ROUTINE_1", "recommendation:completed",
                        "Daily Wellness", "easy", "10 min", now),
                // ── Games ─────────────────────────────────────────
                seedChallenge(
                        "Daily Focus Game",
                        "Play a focus-boosting game to sharpen your concentration today.",
                        "Short mental exercises can support cognitive engagement and focus.",
                        ChallengeType.GAME_ACTIVITY, ChallengeFrequency.DAILY, 1,
                        15, "Focus Boost", "GAME_FOCUS_1", "always",
                        "Focus", "easy", "5 min", now),
                seedChallenge(
                        "Weekly Cognitive Challenge",
                        "Complete 3 game sessions this week to keep your mind active.",
                        "Regular mental challenges can help maintain cognitive sharpness.",
                        ChallengeType.GAME_ACTIVITY, ChallengeFrequency.WEEKLY, 3,
                        40, "Cognitive Champion Badge", "GAME_COGNITIVE_3", "always",
                        "Memory", "medium", "5 min", now));

        repository.saveAll(challenges);
        log.info("Seeded {} challenges.", challenges.size());
    }

    private static Challenge seedChallenge(String title, String description, String why,
                                           ChallengeType type, ChallengeFrequency frequency,
                                           int target, int points, String reward, String badgeCode,
                                           String eligibilityRule, String category,
                                           String difficulty, String estimatedDuration, Instant now) {
        Challenge c = new Challenge();
        c.setTitle(title);
        c.setDescription(description);
        c.setWhy(why);
        c.setType(type.name());
        c.setFrequency(frequency.name());
        c.setTarget(target);
        c.setDurationDays(frequency == ChallengeFrequency.DAILY ? 1 : 7);
        c.setPoints(points);
        c.setReward(reward);
        c.setBadgeCode(badgeCode);
        c.setEligibilityRule(eligibilityRule);
        c.setCategory(category);
        c.setDifficulty(difficulty);
        c.setEstimatedDuration(estimatedDuration);
        c.setActive(true);
        c.setVersion(1);
        c.setCreatedAt(now);
        c.setUpdatedAt(now);
        return c;
    }
}
