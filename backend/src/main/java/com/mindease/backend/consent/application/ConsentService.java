package com.mindease.backend.consent.application;

import java.time.Instant;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.common.logging.AuditLog;
import com.mindease.backend.consent.domain.ConsentRecord;
import com.mindease.backend.consent.domain.ConsentRepository;
import com.mindease.backend.consent.domain.ConsentType;
import com.mindease.backend.consent.dto.ConsentRequest;
import com.mindease.backend.consent.dto.ConsentResponse;
import com.mindease.backend.user.domain.ConsentStatus;
import com.mindease.backend.user.domain.User;
import com.mindease.backend.user.domain.UserRepository;

/**
 * Consent workflow. Consent is never assumed: screening is blocked until all
 * four required consent types are explicitly accepted (see ScreeningService).
 */
@Service
public class ConsentService {

    public static final String CURRENT_POLICY_VERSION = "1.0";

    private static final Set<ConsentType> REQUIRED = EnumSet.of(
            ConsentType.PRIVACY_POLICY,
            ConsentType.TERMS_AND_CONDITIONS,
            ConsentType.AI_ANALYSIS,
            ConsentType.SECURE_STORAGE);

    private final ConsentRepository consents;
    private final UserRepository users;
    private final AuditLog audit;

    public ConsentService(ConsentRepository consents, UserRepository users, AuditLog audit) {
        this.consents = consents;
        this.users = users;
        this.audit = audit;
    }

    public ConsentResponse myConsents(String userId) {
        List<ConsentRecord> records = consents.findByUserId(userId);
        boolean completed = REQUIRED.stream()
                .allMatch(type -> records.stream()
                        .anyMatch(r -> r.getConsentType() == type && r.isAccepted()));
        return ConsentResponse.of(records, completed);
    }

    /** Records all four accepted consents and mirrors completion on the account. */
    public ConsentResponse accept(String userId, ConsentRequest request) {
        if (!request.accepted().equals(REQUIRED)) {
            throw new ApiException(ErrorCode.VALIDATION_FAILED,
                    "All required consents must be accepted before you can continue.");
        }
        String policyVersion = request.policyVersion() == null || request.policyVersion().isBlank()
                ? CURRENT_POLICY_VERSION
                : request.policyVersion();

        for (ConsentType type : REQUIRED) {
            upsert(userId, type, policyVersion);
        }

        User user = users.findById(userId).orElseThrow(
                () -> new ApiException(ErrorCode.UNAUTHORIZED, "Account not found"));
        if (user.getConsentStatus() != ConsentStatus.COMPLETED) {
            user.setConsentStatus(ConsentStatus.COMPLETED);
            user.setUpdatedAt(Instant.now());
            users.save(user);
        }

        audit.event(userId, "consent.accepted", "required consents recorded");
        return myConsents(userId);
    }

    /** Idempotent: updates an existing row rather than creating duplicates. */
    private void upsert(String userId, ConsentType type, String policyVersion) {
        ConsentRecord record = consents.findByUserIdAndConsentType(userId, type)
                .orElseGet(() -> new ConsentRecord(userId, type, true, policyVersion, Instant.now()));
        record.setAccepted(true);
        record.setPolicyVersion(policyVersion);
        record.setAcceptedAt(Instant.now());
        consents.save(record);
    }
}