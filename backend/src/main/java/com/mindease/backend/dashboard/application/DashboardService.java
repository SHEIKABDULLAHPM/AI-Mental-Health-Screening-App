package com.mindease.backend.dashboard.application;

import org.springframework.stereotype.Service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.dashboard.dto.DashboardDto;
import com.mindease.backend.personalization.application.PersonalizationService;
import com.mindease.backend.personalization.domain.PersonalizedContext;
import com.mindease.backend.user.domain.User;
import com.mindease.backend.user.domain.UserRepository;
import com.mindease.backend.user.dto.UserProfileDto;
import com.mindease.backend.wellness.application.WellnessProfileService;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * Builds the dashboard payload for the caller. Requires an authenticated
 * account; a missing wellness profile simply yields the pending AI state.
 */
@Service
public class DashboardService {

    private static final Logger log = LoggerFactory.getLogger(DashboardService.class);

    private final UserRepository users;
    private final WellnessProfileService profiles;
    private final PersonalizationService personalizationService;

    public DashboardService(UserRepository users, WellnessProfileService profiles,
            PersonalizationService personalizationService) {
        this.users = users;
        this.profiles = profiles;
        this.personalizationService = personalizationService;
    }

    public DashboardDto dashboardFor(String userId) {
        User user = users.findById(userId)
                .orElseThrow(() -> new ApiException(ErrorCode.UNAUTHORIZED, "Account not found"));
        WellnessProfileDto profile = null;
        try {
            profile = profiles.currentUser(userId);
        } catch (ApiException ignored) {
            // No profile yet - the dashboard renders the pending AI state.
        }

        // Build personalization summary for the dashboard
        DashboardDto.PersonalizationSummary personalizationSummary = null;
        try {
            PersonalizedContext pCtx = personalizationService.getContext(userId);
            personalizationSummary = new DashboardDto.PersonalizationSummary(
                    pCtx.getCurrentMood(),
                    pCtx.getMoodTrend(),
                    pCtx.getDominantMood(),
                    pCtx.isJournalAvailable(),
                    pCtx.getRecentJournalCount(),
                    pCtx.getPersonalizationSummary());
        } catch (Exception e) {
            log.debug("Could not build personalization summary for dashboard: {}", e.getMessage());
        }

        return DashboardDto.of(
                UserProfileDto.from(user),
                greetingName(user.getFullName()),
                profile,
                personalizationSummary);
    }

    private String greetingName(String fullName) {
        if (fullName == null || fullName.isBlank()) {
            return "there";
        }
        String[] parts = fullName.trim().split("\\s+");
        return parts[0];
    }
}