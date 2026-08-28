package com.mindease.backend.features.relax.application;

import java.time.Instant;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.relax.domain.RelaxActivity;
import com.mindease.backend.features.relax.domain.RelaxActivityRepository;
import com.mindease.backend.features.relax.domain.UserRelaxCompletion;
import com.mindease.backend.features.relax.domain.UserRelaxCompletionRepository;
import com.mindease.backend.features.relax.dto.RelaxActivityResponse;

@Service
public class RelaxService {

    private final RelaxActivityRepository activityRepository;
    private final UserRelaxCompletionRepository completionRepository;

    public RelaxService(RelaxActivityRepository activityRepository,
                        UserRelaxCompletionRepository completionRepository) {
        this.activityRepository = activityRepository;
        this.completionRepository = completionRepository;
    }

    public List<RelaxActivityResponse> getActivities(String userId, Optional<String> category) {
        List<RelaxActivity> activities = category
                .filter(c -> !c.isBlank())
                .map(c -> activityRepository.findByActiveTrueAndCategoryOrderByTitleAsc(c))
                .orElseGet(() -> activityRepository.findByActiveTrueOrderByCategoryAscTitleAsc());

        List<String> completedIds = activities.stream()
                .map(RelaxActivity::getId)
                .filter(id -> hasCompletedToday(userId, id))
                .collect(Collectors.toList());

        return activities.stream()
                .map(a -> RelaxActivityResponse.from(a, completedIds.contains(a.getId())))
                .collect(Collectors.toList());
    }

    public RelaxActivityResponse getActivityById(String userId, String id) {
        RelaxActivity activity = activityRepository.findByIdAndActiveTrue(id)
                .orElseThrow(() -> ApiException.notFound("Relax activity not found or no longer available."));

        boolean completed = hasCompletedToday(userId, id);
        return RelaxActivityResponse.from(activity, completed);
    }

    public RelaxActivityResponse completeActivity(String userId, String activityId) {
        RelaxActivity activity = activityRepository.findByIdAndActiveTrue(activityId)
                .orElseThrow(() -> ApiException.notFound("Relax activity not found or no longer available."));

        if (hasCompletedToday(userId, activityId)) {
            throw ApiException.badRequest("You have already completed this activity today.");
        }

        UserRelaxCompletion completion = new UserRelaxCompletion();
        completion.setUserId(userId);
        completion.setActivityId(activityId);
        completion.setCompletedAt(Instant.now());

        completionRepository.save(completion);

        return RelaxActivityResponse.from(activity, true);
    }

    private boolean hasCompletedToday(String userId, String activityId) {
        Instant startOfDay = Instant.now().atZone(java.time.ZoneOffset.UTC)
                .toLocalDate()
                .atStartOfDay(java.time.ZoneOffset.UTC)
                .toInstant();
        Instant endOfDay = startOfDay.plusSeconds(86400);

        Optional<UserRelaxCompletion> today = completionRepository
                .findByUserIdAndActivityIdAndCompletedAtBetween(userId, activityId, startOfDay, endOfDay);

        return today.isPresent();
    }
}
