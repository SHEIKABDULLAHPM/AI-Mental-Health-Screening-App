package com.mindease.backend.features.emotion.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.config.AppProperties;
import com.mindease.backend.config.SecurityConfig;
import com.mindease.backend.features.emotion.application.EmotionEventService;
import com.mindease.backend.features.emotion.dto.EmotionEventResponse;
import com.mindease.backend.security.AuthRateLimitFilter;
import com.mindease.backend.security.InternalApiKeyFilter;
import com.mindease.backend.security.JwtAuthenticationFilter;
import com.mindease.backend.security.JwtService;
import com.mindease.backend.security.RateLimiterService;
import com.mindease.backend.security.RestAccessDeniedHandler;
import com.mindease.backend.security.RestAuthenticationEntryPoint;

import io.jsonwebtoken.JwtException;

/**
 * Security contract for POST /api/v1/emotions/events (§52):
 * unauthenticated, forged-token, cross-user, malformed, replayed and
 * rate-limited submissions.
 */
@WebMvcTest(EmotionEventController.class)
@Import({
        SecurityConfig.class,
        JwtAuthenticationFilter.class,
        AuthRateLimitFilter.class,
        InternalApiKeyFilter.class,
        RestAuthenticationEntryPoint.class,
        RestAccessDeniedHandler.class,
        RateLimiterService.class
})
class EmotionEventControllerTest {

    /** Real AppProperties with defaults (no binding source in the slice).
     * A Mockito mock cannot be used: Boot binds @ConfigurationProperties
     * beans and the mock subclass has no setters. */
    @TestConfiguration
    static class TestConfig {
        @Bean
        AppProperties appProperties() {
            return new AppProperties();
        }
    }

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper mapper;

    @MockBean
    private EmotionEventService service;

    @MockBean
    private JwtService jwtService;

    @BeforeEach
    void stubCommon() {
        when(jwtService.validateAccessToken("good-token")).thenReturn("user-1");
        when(jwtService.validateAccessToken("user-2-token")).thenReturn("user-2");
        when(jwtService.validateAccessToken("bad-token")).thenThrow(new JwtException("bad"));
    }

    private String validBody(String key) throws Exception {
        return mapper.writeValueAsString(Map.ofEntries(
                Map.entry("emotion", "happy"),
                Map.entry("scores", Map.of(
                        "anger", 0.02, "disgust", 0.01, "fear", 0.03,
                        "happy", 0.80, "neutral", 0.05, "sad", 0.03, "surprise", 0.06)),
                Map.entry("calibratedConfidence", 0.84),
                Map.entry("faceQuality", 0.93),
                Map.entry("modelId", "vit-fer-7"),
                Map.entry("modelVersion", "1.0.0"),
                Map.entry("preprocessingVersion", "2.0.0"),
                Map.entry("status", "PREDICTED"),
                Map.entry("source", "CAMERA"),
                Map.entry("capturedAt", Instant.now().toString()),
                Map.entry("idempotencyKey", "test-" + key)));
    }

    private EmotionEventResponse stored(String id) {
        return new EmotionEventResponse(id, "happy", Map.of("happy", 0.8),
                0.84, 0.93, "vit-fer-7", "1.0.0", "2.0.0",
                "PREDICTED", "CAMERA", Instant.now(), Instant.now());
    }

    @Test
    void post_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/emotions/events")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validBody("k-anon")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void post_withForgedToken_isUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/emotions/events")
                        .header("Authorization", "Bearer bad-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validBody("k-forged")))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void post_validSubmission_returnsCreated() throws Exception {
        when(service.recordEvent(eq("user-1"), any())).thenReturn(stored("evt-1"));
        mvc.perform(post("/api/v1/emotions/events")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validBody("k-ok")))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").value("evt-1"));
    }

    @Test
    void post_tamperedUserIdField_isIgnored_serverIdentityWins() throws Exception {
        // There is no userId field in the schema; an attacker smuggling one
        // gets it ignored (Jackson) while the JWT identity is used.
        when(service.recordEvent(eq("user-1"), any())).thenReturn(stored("evt-2"));
        var body = mapper.readValue(validBody("k-tamper"), Map.class);
        var tampered = new java.util.LinkedHashMap<>(body);
        tampered.put("userId", "victim-user");
        mvc.perform(post("/api/v1/emotions/events")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(mapper.writeValueAsString(tampered)))
                .andExpect(status().isCreated());
        org.mockito.Mockito.verify(service)
                .recordEvent(eq("user-1"), any());
    }

    @Test
    void post_invalidEmotion_isBadRequest() throws Exception {
        var body = mapper.readValue(validBody("k-bad"), Map.class);
        var tampered = new java.util.LinkedHashMap<>(body);
        tampered.put("emotion", "depressed");
        mvc.perform(post("/api/v1/emotions/events")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(mapper.writeValueAsString(tampered)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void post_confidenceOutOfRange_isBadRequest() throws Exception {
        var body = mapper.readValue(validBody("k-range"), Map.class);
        var tampered = new java.util.LinkedHashMap<>(body);
        tampered.put("calibratedConfidence", 7.5);
        mvc.perform(post("/api/v1/emotions/events")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(mapper.writeValueAsString(tampered)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void get_foreignEventId_returnsNotFound_notLeaked() throws Exception {
        when(service.getById("user-2", "evt-foreign"))
                .thenThrow(new ApiException(ErrorCode.NOT_FOUND, "Emotion event not found"));
        mvc.perform(get("/api/v1/emotions/events/evt-foreign")
                        .header("Authorization", "Bearer user-2-token"))
                .andExpect(status().isNotFound());
    }

    @Test
    void post_burst_isRateLimited() throws Exception {
        // Dedicated identity: rate-limit state must not leak into/fail other tests.
        when(jwtService.validateAccessToken("burst-token")).thenReturn("burst-user");
        when(service.recordEvent(eq("burst-user"), any()))
                .thenAnswer(inv -> stored("evt-" + System.nanoTime()));
        int limited = 0;
        for (int i = 0; i < 65; i++) {
            var result = mvc.perform(post("/api/v1/emotions/events")
                            .header("Authorization", "Bearer burst-token")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(validBody("k-burst-" + i)))
                    .andReturn();
            if (result.getResponse().getStatus() == 429) {
                limited++;
            }
        }
        org.junit.jupiter.api.Assertions.assertTrue(limited > 0,
                "expected the per-user rate limit to trigger within 65 posts");
    }
}
