package com.mindease.backend.screening.domain;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

/** Stores the singleton screening questionnaire catalog. */
public interface QuestionnaireCatalogRepository extends MongoRepository<QuestionnaireCatalog, String> {

    Optional<QuestionnaireCatalog> findFirstByOrderByCreatedAtDesc();
}
