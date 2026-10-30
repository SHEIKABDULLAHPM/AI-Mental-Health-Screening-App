package com.mindease.backend.security;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Extracts the {@code X-User-Timezone} header from the incoming request and
 * stores it in {@link UserTimeZoneHolder} for the duration of the request.
 * This allows services to access the user's timezone without passing it through
 * every method signature.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class UserTimeZoneFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        try {
            String zone = request.getHeader("X-User-Timezone");
            if (zone != null && !zone.isBlank()) {
                UserTimeZoneHolder.set(zone.trim());
            }
            filterChain.doFilter(request, response);
        } finally {
            UserTimeZoneHolder.clear();
        }
    }
}
