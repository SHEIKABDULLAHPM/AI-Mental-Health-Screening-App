package com.mindease.backend;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;

import com.mindease.backend.features.challenges.domain.ChallengeRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationContentRepository;
import com.mindease.backend.features.recommendations.domain.RecommendationInteractionRepository;
import com.mindease.backend.features.relax.domain.RelaxActivityRepository;
import com.mindease.backend.screening.domain.QuestionnaireCatalogRepository;

/**
 * Verifies the application context loads.
 * Excludes external infra via the `test` profile and mocks every seeder
 * repository so context load never requires a live Mongo.
 */
@SpringBootTest
@ActiveProfiles("test")
class MindEaseApplicationTests {

    @MockBean
    private QuestionnaireCatalogRepository questionnaireCatalogRepository;

    @MockBean
    private ChallengeRepository challengeRepository;

    @MockBean
    private RecommendationContentRepository recommendationContentRepository;

    @MockBean
    private RecommendationInteractionRepository recommendationInteractionRepository;

    @MockBean
    private RelaxActivityRepository relaxActivityRepository;

    @Test
    void contextLoads(ApplicationContext context) {
        assertThat(context).isNotNull();
    }
}