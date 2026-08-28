package com.mindease.backend.features.relax.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface RelaxActivityRepository extends MongoRepository<RelaxActivity, String> {

    List<RelaxActivity> findByActiveTrueOrderByCategoryAscTitleAsc();

    List<RelaxActivity> findByActiveTrueAndCategoryOrderByTitleAsc(String category);

    Optional<RelaxActivity> findByIdAndActiveTrue(String id);
}
