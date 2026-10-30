package com.mindease.backend.dashboard.dto;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * The dashboard must surface a positive PHQ-9 item-9 screen independently of
 * whether the AI narrative has completed.
 */
class DashboardDtoTest {

    private WellnessProfileDto profile(ProfileStatus status, Boolean safetyFlag) {
        WellnessProfile profile = new WellnessProfile();
        profile.setId("profile-1");
        profile.setAssessmentId("assessment-1");
        profile.setStatus(status);
        profile.setSafetyFlag(safetyFlag);
        return WellnessProfileDto.from(profile);
    }

    @Test
    void safetyFlagIsExposedWhileTheAiInsightIsStillPending() {
        DashboardDto dto = DashboardDto.of(null, "there",
                profile(ProfileStatus.AI_ANALYSIS_PENDING, true));

        assertThat(dto.safetyFlag()).isTrue();
        assertThat(dto.aiReady()).isFalse();
    }

    @Test
    void safetyFlagIsExposedAfterCompletion() {
        DashboardDto dto = DashboardDto.of(null, "there",
                profile(ProfileStatus.COMPLETED, true));

        assertThat(dto.safetyFlag()).isTrue();
    }

    @Test
    void absentProfileMeansNoSafetyEscalation() {
        DashboardDto dto = DashboardDto.of(null, "there", null);

        assertThat(dto.safetyFlag()).isFalse();
    }
}
