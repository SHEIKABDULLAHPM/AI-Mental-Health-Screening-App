package com.mindease.backend.screening.application;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.screening.domain.QuestionnaireCatalog;
import com.mindease.backend.screening.domain.QuestionnaireCatalogRepository;

/**
 * Serves the questionnaire catalog the screening UI renders. The catalog is
 * seeded at startup and never hardcoded in the client.
 */
@Service
public class QuestionnaireCatalogService {

    private final QuestionnaireCatalogRepository repository;

    public QuestionnaireCatalogService(QuestionnaireCatalogRepository repository) {
        this.repository = repository;
    }

    public QuestionnaireCatalog current() {
        return repository.findFirstByOrderByCreatedAtDesc()
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND,
                        "The questionnaire catalog is not available yet. Please try again shortly."));
    }
}
