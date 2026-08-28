package com.mindease.backend.consent.dto;

import java.time.Instant;
import java.util.List;

import com.mindease.backend.consent.domain.ConsentRecord;
import com.mindease.backend.consent.domain.ConsentType;

/** Consent status for one user. */
public record ConsentResponse(
        boolean completed,
        List<ConsentItem> consents) {

    public record ConsentItem(
            ConsentType type,
            boolean accepted,
            String policyVersion,
            Instant acceptedAt) {

        public static ConsentItem from(ConsentRecord record) {
            return new ConsentItem(record.getConsentType(), record.isAccepted(),
                    record.getPolicyVersion(), record.getAcceptedAt());
        }
    }

    public static ConsentResponse of(List<ConsentRecord> records, boolean completed) {
        List<ConsentItem> items = records.stream().map(ConsentItem::from).toList();
        return new ConsentResponse(completed, items);
    }
}