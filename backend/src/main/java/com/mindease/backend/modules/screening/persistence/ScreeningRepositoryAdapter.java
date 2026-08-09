package com.mindease.backend.modules.screening.persistence;

import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Repository;

import com.mindease.backend.modules.screening.domain.Screening;
import com.mindease.backend.modules.screening.domain.ScreeningRepository;

/**
 * Maps the domain repository contract to the MongoDB adapter.
 */
@Repository
public class ScreeningRepositoryAdapter implements ScreeningRepository {

    private final MongoScreeningRepository mongo;

    public ScreeningRepositoryAdapter(MongoScreeningRepository mongo) {
        this.mongo = mongo;
    }

    @Override
    public Screening save(Screening screening) {
        return mongo.save(screening);
    }

    @Override
    public Optional<Screening> findById(String id) {
        return mongo.findById(id);
    }

    @Override
    public List<Screening> findByUserId(String userId) {
        return mongo.findByUserId(userId);
    }
}