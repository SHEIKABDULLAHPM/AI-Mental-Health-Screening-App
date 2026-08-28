package com.mindease.backend.features.relax.application;

import java.time.Instant;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import com.mindease.backend.features.relax.domain.RelaxActivity;
import com.mindease.backend.features.relax.domain.RelaxActivityRepository;

@Component
public class RelaxSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(RelaxSeeder.class);

    private final RelaxActivityRepository repository;

    public RelaxSeeder(RelaxActivityRepository repository) {
        this.repository = repository;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (repository.count() > 0) {
            log.info("Relax activities already present, skipping seed.");
            return;
        }

        Instant now = Instant.now();
        List<RelaxActivity> activities = List.of(
                seedActivity("Box breathing",
                        "Inhale for 4 seconds, hold for 4, exhale for 4, hold for 4. Repeat.",
                        "breathing", 3, 0xea4e, now),
                seedActivity("4-7-8 breathing",
                        "Inhale for 4 seconds, hold for 7, exhale for 8. A calming technique.",
                        "breathing", 2, 0xea4e, now),
                seedActivity("Body scan",
                        "Slowly bring awareness to each part of your body from toes to head.",
                        "meditation", 10, 0xe504, now),
                seedActivity("Calm mind",
                        "A guided meditation to clear your mind and find inner stillness.",
                        "meditation", 5, 0xe504, now),
                seedActivity("Ocean waves",
                        "Relax to the soothing sound of ocean waves crashing on the shore.",
                        "music", 15, 0xe405, now),
                seedActivity("Rainfall",
                        "Gentle rainfall sounds to help you unwind and fall asleep.",
                        "sounds", 60, 0xe445, now));

        repository.saveAll(activities);
        log.info("Seeded {} relax activities.", activities.size());
    }

    private static RelaxActivity seedActivity(String title, String description,
                                               String category, int durationMinutes,
                                               int iconCodePoint, Instant now) {
        RelaxActivity a = new RelaxActivity();
        a.setTitle(title);
        a.setDescription(description);
        a.setCategory(category);
        a.setDurationMinutes(durationMinutes);
        a.setIconCodePoint(iconCodePoint);
        a.setActive(true);
        a.setCreatedAt(now);
        return a;
    }
}
