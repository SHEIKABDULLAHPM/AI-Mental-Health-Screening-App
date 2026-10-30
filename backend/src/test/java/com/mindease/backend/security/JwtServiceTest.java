package com.mindease.backend.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.mindease.backend.config.AppProperties;

/**
 * Regression tests for token uniqueness.
 *
 * <p>Refresh tokens are persisted under a unique {@code tokenHash} index. When
 * two tokens for the same user were minted inside the same clock second they
 * were byte-identical, so a rapid second login raised a
 * {@code DuplicateKeyException} that surfaced to the user as HTTP 500. Every
 * issuance must therefore be distinguishable.</p>
 */
class JwtServiceTest {

    private static final String USER = "user-abc";
    private static final String SECRET =
            "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=";

    private JwtService service;

    @BeforeEach
    void setUp() {
        AppProperties props = new AppProperties();
        props.getJwt().setSecret(SECRET);
        props.getJwt().setIssuer("mindease");
        service = new JwtService(props);
    }

    /**
     * The exact condition that used to break: identical user and identical
     * instant, i.e. two logins within the same second.
     */
    @Test
    void refreshTokensMintedInTheSameInstantAreDistinct() {
        Instant now = Instant.parse("2026-10-02T19:57:35Z");

        String first = service.createRefreshToken(USER, now);
        String second = service.createRefreshToken(USER, now);

        assertThat(first).isNotEqualTo(second);
    }

    @Test
    void accessTokensMintedInTheSameInstantAreDistinct() {
        Instant now = Instant.parse("2026-10-02T19:57:35Z");

        String first = service.createAccessToken(USER, now);
        String second = service.createAccessToken(USER, now);

        assertThat(first).isNotEqualTo(second);
    }

    @Test
    void manyRapidIssuancesNeverCollide() {
        Instant now = Instant.now();
        Set<String> hashes = new HashSet<>();
        for (int i = 0; i < 200; i++) {
            hashes.add(service.createRefreshToken(USER, now));
        }

        assertThat(hashes).hasSize(200);
    }

    @Test
    void accessTokenValidatesAndKindsStayDistinct() {
        Instant now = Instant.now();
        String access = service.createAccessToken(USER, now);
        String refresh = service.createRefreshToken(USER, now);

        assertThat(service.validateAccessToken(access)).isEqualTo(USER);
        // The token kinds must stay distinguishable.
        assertThat(access).isNotEqualTo(refresh);
    }
}