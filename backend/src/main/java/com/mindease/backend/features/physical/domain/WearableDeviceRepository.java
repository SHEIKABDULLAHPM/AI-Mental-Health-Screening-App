package com.mindease.backend.features.physical.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface WearableDeviceRepository extends MongoRepository<WearableDevice, String> {

    List<WearableDevice> findByUserIdOrderByUpdatedAtDesc(String userId);

    Optional<WearableDevice> findByIdAndUserId(String id, String userId);

    Optional<WearableDevice> findByUserIdAndDeviceIdentifier(String userId, String deviceIdentifier);

    void deleteByIdAndUserId(String id, String userId);
}
