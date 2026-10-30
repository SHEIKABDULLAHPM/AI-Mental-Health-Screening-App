package com.mindease.backend.security;

import java.time.Instant;
import java.util.Date;
import java.util.UUID;

import javax.crypto.SecretKey;

import org.springframework.stereotype.Service;

import com.mindease.backend.config.AppProperties;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;

/**
 * Creates and verifies self-issued HS256 JWTs.
 *
 * <p>Only the user identity is signed (the subject is the user id). Never
 * place passwords, OTPs or other secrets inside the token.</p>
 */
@Service
public class JwtService {

    private final SecretKey key;
    private final String issuer;
    private final long accessMillis;
    private final long refreshMillis;

    public JwtService(AppProperties props) {
        AppProperties.Jwt jwt = props.getJwt();
        String secret = jwt.getSecret();
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("mindease.jwt.secret is not configured (MINDEASE_JWT_SECRET)");
        }
        this.key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret));
        this.issuer = jwt.getIssuer();
        this.accessMillis = jwt.getAccessExpiration().toMillis();
        this.refreshMillis = jwt.getRefreshExpiration().toMillis();
    }

    /**
     * Fresh unique token id.
     *
     * <p>Without a per-issuance random claim, two tokens minted for the same
     * user inside the same clock second are byte-identical (same subject, issuer,
     * iat and exp). Refresh tokens are stored under a unique {@code tokenHash}
     * index, so a rapid second login collided and surfaced as a 500. Every
     * issuance now carries a distinct {@code jti}.</p>
     */
    private String newTokenId() {
        return UUID.randomUUID().toString();
    }

    public String createAccessToken(String userId, Instant now) {
        return Jwts.builder()
                .id(newTokenId())
                .subject(userId)
                .issuer(issuer)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusSeconds(accessMillis / 1000)))
                .claim("tok", "access")
                .signWith(key)
                .compact();
    }

    public String createRefreshToken(String userId, Instant now) {
        return Jwts.builder()
                .id(newTokenId())
                .subject(userId)
                .issuer(issuer)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusSeconds(refreshMillis / 1000)))
                .claim("tok", "refresh")
                .signWith(key)
                .compact();
    }

    /**
     * Validates an access token, returning its subject (user id) or throwing
     * {@link JwtException} when invalid/expired/the wrong token kind.
     */
    public String validateAccessToken(String token) throws JwtException {
        Claims claims = parse(token);
        if (!"access".equals(claims.get("tok", String.class)) || claims.getSubject() == null) {
            throw new JwtException("Not an access token");
        }
        return claims.getSubject();
    }

    private Claims parse(String token) throws JwtException {
        return Jwts.parser()
                .verifyWith(key)
                .requireIssuer(issuer)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public long getRefreshExpirationSeconds() {
        return refreshMillis / 1000;
    }
}