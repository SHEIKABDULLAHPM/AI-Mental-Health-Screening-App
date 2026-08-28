package com.mindease.backend.consent.dto;

import java.util.EnumSet;
import java.util.Set;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.mindease.backend.consent.domain.ConsentType;

/**
 * Payload confirming the four required consents. The backend only trusts
 * explicit booleans — silence is never treated as consent.
 */
public record ConsentRequest(
        @JsonProperty("privacyPolicy") Boolean privacyPolicy,
        @JsonProperty("termsAndConditions") Boolean termsAndConditions,
        @JsonProperty("aiAnalysis") Boolean aiAnalysis,
        @JsonProperty("secureStorage") Boolean secureStorage,
        String policyVersion) {

    /** Set of consent types explicitly accepted in this request. */
    public Set<ConsentType> accepted() {
        Set<ConsentType> set = EnumSet.noneOf(ConsentType.class);
        if (Boolean.TRUE.equals(privacyPolicy)) {
            set.add(ConsentType.PRIVACY_POLICY);
        }
        if (Boolean.TRUE.equals(termsAndConditions)) {
            set.add(ConsentType.TERMS_AND_CONDITIONS);
        }
        if (Boolean.TRUE.equals(aiAnalysis)) {
            set.add(ConsentType.AI_ANALYSIS);
        }
        if (Boolean.TRUE.equals(secureStorage)) {
            set.add(ConsentType.SECURE_STORAGE);
        }
        return set;
    }
}