package com.mindease.backend.security;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;

/**
 * Resolves the authenticated caller id from the Spring Security context.
 *
 * <p>Ownership checks ALWAYS use this value - never a userId supplied by the
 * client.</p>
 */
public final class AuthenticatedUser {

    private AuthenticatedUser() {
    }

    public static String currentId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || auth.getPrincipal() == null) {
            throw new ApiException(ErrorCode.UNAUTHORIZED, "Authentication required");
        }
        return auth.getPrincipal().toString();
    }
}