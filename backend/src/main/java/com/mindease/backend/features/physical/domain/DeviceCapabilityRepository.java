package com.mindease.backend.features.physical.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface DeviceCapabilityRepository extends MongoRepository<DeviceCapability, String> {

    List<DeviceCapability> findByUserIdAndDeviceIdOrderByMetricAsc(String userId, String deviceId);

    Optional<DeviceCapability> findByUserIdAndDeviceIdAndMetric(
            String userId, String deviceId, String metric);

    void deleteByUserIdAndDeviceId(String userId, String deviceId);
}
