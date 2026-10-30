package com.mindease.backend.screening.domain;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A screening assessment (personal + lifestyle + PHQ-9 / GAD-7 / PSS / WHO-5).
 * Responses are stored exactly as entered by the UI and validated server-side
 * before the assessment may be completed.
 */
@Document(collection = "screenings")
public class Screening {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String tenantId = "app";

    private ScreeningStatus status = ScreeningStatus.IN_PROGRESS;

    private PersonalInfo personal = new PersonalInfo();

    private Lifestyle lifestyle = new Lifestyle();

    /** Questionnaire answers keyed by code, e.g. "phq9" -> [0,1,2,...]. */
    private Map<String, List<Integer>> assessments = new LinkedHashMap<>();

    /**
     * Optional onboarding mood assessment snapshot (user-provided only).
     * Null for assessments created before the Mood Check-In integration or by
     * older clients — always handled gracefully downstream.
     */
    private MoodAssessment mood;

    /**
     * Version of the questionnaire catalog the answers were given against.
     * Stamped server-side so scores stay reproducible when the catalog evolves.
     */
    private String catalogVersion;

    private Instant startedAt;

    private Instant updatedAt;

    private Instant completedAt;

    public Screening() {
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public ScreeningStatus getStatus() {
        return status;
    }

    public void setStatus(ScreeningStatus status) {
        this.status = status;
    }

    public PersonalInfo getPersonal() {
        return personal;
    }

    public void setPersonal(PersonalInfo personal) {
        this.personal = personal;
    }

    public Lifestyle getLifestyle() {
        return lifestyle;
    }

    public void setLifestyle(Lifestyle lifestyle) {
        this.lifestyle = lifestyle;
    }

    public Map<String, List<Integer>> getAssessments() {
        return assessments;
    }

    /**
     * PHQ-9 item 9 screens for thoughts of being better off dead or of
     * self-harm. Any non-zero response is a positive screen. This is a safety
     * signal only: it never changes the wellness score and is not a diagnosis.
     */
    public boolean hasSelfHarmSignal() {
        if (assessments == null) {
            return false;
        }
        List<Integer> phq9 = assessments.get("phq9");
        if (phq9 == null || phq9.size() < 9) {
            return false;
        }
        Integer item9 = phq9.get(8);
        return item9 != null && item9 > 0;
    }

    public void setAssessments(Map<String, List<Integer>> assessments) {
        this.assessments = assessments;
    }

    public MoodAssessment getMood() {
        return mood;
    }

    public void setMood(MoodAssessment mood) {
        this.mood = mood;
    }

    public String getCatalogVersion() {
        return catalogVersion;
    }

    public void setCatalogVersion(String catalogVersion) {
        this.catalogVersion = catalogVersion;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(Instant startedAt) {
        this.startedAt = startedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }

    public void setCompletedAt(Instant completedAt) {
        this.completedAt = completedAt;
    }
}