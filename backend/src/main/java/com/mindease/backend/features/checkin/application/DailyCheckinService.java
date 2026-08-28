package com.mindease.backend.features.checkin.application;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.checkin.domain.DailyCheckin;
import com.mindease.backend.features.checkin.domain.DailyCheckinRepository;
import com.mindease.backend.features.checkin.dto.CheckinResponse;
import com.mindease.backend.features.checkin.dto.CreateCheckinRequest;
import com.mindease.backend.features.checkin.dto.UpdateCheckinRequest;

@Service
public class DailyCheckinService {

    private final DailyCheckinRepository repository;

    public DailyCheckinService(DailyCheckinRepository repository) {
        this.repository = repository;
    }

    public CheckinResponse createCheckin(String userId, CreateCheckinRequest request) {
        LocalDate today = LocalDate.now();
        Optional<DailyCheckin> existing = repository.findByUserIdAndDate(userId, today);
        if (existing.isPresent()) {
            throw new ApiException(ErrorCode.CONFLICT,
                    "A check-in already exists for today. Use PUT to update it.");
        }

        DailyCheckin checkin = new DailyCheckin(
                userId,
                today,
                request.mood(),
                request.sleep(),
                request.energy(),
                request.stress(),
                request.activities());

        repository.save(checkin);
        return CheckinResponse.from(checkin);
    }

    public CheckinResponse getTodayCheckin(String userId) {
        Optional<DailyCheckin> checkin = repository.findByUserIdAndDate(userId, LocalDate.now());
        return checkin.map(CheckinResponse::from).orElse(null);
    }

    public List<CheckinResponse> getCheckinHistory(String userId, int page, int size) {
        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "date"));
        List<DailyCheckin> checkins = repository.findByUserIdOrderByDateDesc(userId, pageable);
        return checkins.stream().map(CheckinResponse::from).toList();
    }

    public CheckinResponse getCheckinById(String userId, String checkinId) {
        DailyCheckin checkin = repository.findById(checkinId)
                .orElseThrow(() -> ApiException.notFound("Check-in not found"));
        validateOwnership(checkin, userId);
        return CheckinResponse.from(checkin);
    }

    public CheckinResponse updateCheckin(String userId, String checkinId, UpdateCheckinRequest request) {
        DailyCheckin checkin = repository.findById(checkinId)
                .orElseThrow(() -> ApiException.notFound("Check-in not found"));
        validateOwnership(checkin, userId);

        if (request.mood() != null) {
            checkin.setMood(request.mood());
        }
        if (request.sleep() != null) {
            checkin.setSleep(request.sleep());
        }
        if (request.energy() != null) {
            checkin.setEnergy(request.energy());
        }
        if (request.stress() != null) {
            checkin.setStress(request.stress());
        }
        if (request.activities() != null) {
            checkin.setActivities(request.activities());
        }
        checkin.setUpdatedAt(Instant.now());

        repository.save(checkin);
        return CheckinResponse.from(checkin);
    }

    private void validateOwnership(DailyCheckin checkin, String userId) {
        if (!checkin.getUserId().equals(userId)) {
            throw new ApiException(ErrorCode.FORBIDDEN, "You do not have access to this check-in");
        }
    }
}
