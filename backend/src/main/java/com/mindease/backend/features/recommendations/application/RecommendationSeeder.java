package com.mindease.backend.features.recommendations.application;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class RecommendationSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(RecommendationSeeder.class);

    private final RecommendationService service;

    public RecommendationSeeder(RecommendationService service) {
        this.service = service;
    }

    @Override
    public void run(ApplicationArguments args) {
        service.seedRecommendations();
        log.info("Recommendations seed check complete.");
    }
}
