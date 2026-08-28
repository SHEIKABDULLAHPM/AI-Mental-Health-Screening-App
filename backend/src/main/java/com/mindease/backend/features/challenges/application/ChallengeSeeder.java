package com.mindease.backend.features.challenges.application;

import java.time.Instant;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import com.mindease.backend.features.challenges.domain.Challenge;
import com.mindease.backend.features.challenges.domain.ChallengeRepository;

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
                seedChallenge("Gratitude week",
                        "Practice gratitude daily for 7 days. Write down three things you are grateful for each day.",
                        7, 50, "weekly", now),
                seedChallenge("7-day calm",
                        "Spend at least 10 minutes each day on a calming activity such as meditation, deep breathing, or journaling.",
                        7, 70, "daily", now),
                seedChallenge("Move your body",
                        "Get at least 20 minutes of physical activity each day for 5 days.",
                        5, 60, "daily", now),
                seedChallenge("Sleep reset",
                        "Follow a consistent sleep schedule for 7 days: same bedtime, no screens 30 minutes before sleep.",
                        7, 80, "daily", now));

        repository.saveAll(challenges);
        log.info("Seeded {} challenges.", challenges.size());
    }

    private static Challenge seedChallenge(String title, String description,
                                           int durationDays, int points,
                                           String type, Instant now) {
        Challenge c = new Challenge();
        c.setTitle(title);
        c.setDescription(description);
        c.setDurationDays(durationDays);
        c.setPoints(points);
        c.setType(type);
        c.setActive(true);
        c.setCreatedAt(now);
        c.setUpdatedAt(now);
        return c;
    }
}
