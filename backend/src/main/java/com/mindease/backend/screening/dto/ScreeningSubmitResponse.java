package com.mindease.backend.screening.dto;

import com.mindease.backend.screening.domain.Screening;
import com.mindease.backend.wellness.domain.ProfileStatus;

/** Result of submitting a completed assessment. */
public record ScreeningSubmitResponse(
        Screening screening,
        ProcessingInfo processing) {

    /** Assessment processing state returned to the client. */
    public record ProcessingInfo(
            String status,
            String aiStatus,
            String profileId,
            String jobId) {

        public static ProcessingInfo pending(Screening screening, ProfileStatus profileStatus,
                                             String profileId, String jobId) {
            return new ProcessingInfo(
                    screening.getStatus().name(),
                    profileStatus.name(),
                    profileId,
                    jobId);
        }
    }

    public static ScreeningSubmitResponse completed(Screening screening,
                                                     ProfileStatus profileStatus,
                                                     String profileId,
                                                     String jobId) {
        return new ScreeningSubmitResponse(screening,
                ProcessingInfo.pending(screening, profileStatus, profileId, jobId));
    }
}
