package com.mindease.backend.features.recommendations.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface RecommendationContentRepository extends MongoRepository<RecommendationContent, String> {

    List<RecommendationContent> findByActiveTrue();

    List<RecommendationContent> findByActiveTrueAndCategory(String category);

    List<RecommendationContent> findByActiveTrueAndCategoryIn(List<String> categories);

    Optional<RecommendationContent> findByIdAndActiveTrue(String id);

    List<RecommendationContent> findByActiveTrueAndTagsIn(List<String> tags);

    long countByActiveTrue();
}
