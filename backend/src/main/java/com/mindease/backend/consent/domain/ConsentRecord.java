package com.mindease.backend.consent.domain;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One stored consent fact for a user and consent type.
 */
@Document(collection = "consents")
@CompoundIndex(name = "user_consent_type", def = "{'userId': 1, 'consentType': 1}", unique = true)
public class ConsentRecord {

    @Id
    private String id;

    @Indexed
    private String userId;

    private String tenantId = "app";

    private ConsentType consentType;

    private boolean accepted;

    private String policyVersion;

    private Instant acceptedAt;

    public ConsentRecord() {
    }

    public ConsentRecord(String userId, ConsentType consentType, boolean accepted,
                         String policyVersion, Instant acceptedAt) {
        this.userId = userId;
        this.consentType = consentType;
        this.accepted = accepted;
        this.policyVersion = policyVersion;
        this.acceptedAt = acceptedAt;
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

    public ConsentType getConsentType() {
        return consentType;
    }

    public void setConsentType(ConsentType consentType) {
        this.consentType = consentType;
    }

    public boolean isAccepted() {
        return accepted;
    }

    public void setAccepted(boolean accepted) {
        this.accepted = accepted;
    }

    public String getPolicyVersion() {
        return policyVersion;
    }

    public void setPolicyVersion(String policyVersion) {
        this.policyVersion = policyVersion;
    }

    public Instant getAcceptedAt() {
        return acceptedAt;
    }

    public void setAcceptedAt(Instant acceptedAt) {
        this.acceptedAt = acceptedAt;
    }
}