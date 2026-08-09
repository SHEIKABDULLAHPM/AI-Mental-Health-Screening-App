package com.mindease.backend.modules.screening.application;

import java.util.List;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.modules.screening.domain.Screening;
import com.mindease.backend.modules.screening.domain.ScreeningRepository;

/**
 * Application service for screening workflows.
 * Skeleton only - business rules (scoring, thresholds, AI dispatch) are added here.
 */
@Service
public class ScreeningService {

    private final ScreeningRepository repository;

    public ScreeningService(ScreeningRepository repository) {
        this.repository = repository;
    }

    public Screening submit(Screening screening) {
        return repository.save(screening);
    }

    public Screening getById(String id) {
        return repository.findById(id)
                .orElseThrow(() -> ApiException.notFound("Screening not found: " + id));
    }

    public List<Screening> forUser(String userId) {
        return repository.findByUserId(userId);
    }
}