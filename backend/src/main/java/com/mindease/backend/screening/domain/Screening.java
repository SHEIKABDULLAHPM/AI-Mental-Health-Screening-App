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

    public void setAssessments(Map<String, List<Integer>> assessments) {
        this.assessments = assessments;
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