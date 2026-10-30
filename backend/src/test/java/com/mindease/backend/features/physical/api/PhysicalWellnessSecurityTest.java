package com.mindease.backend.features.physical.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
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
import com.mindease.backend.features.physical.application.PhysicalSyncService;
import com.mindease.backend.features.physical.application.PhysicalWellnessService;
import com.mindease.backend.features.physical.application.WearableDeviceService;
import com.mindease.backend.features.physical.domain.SyncStatus;
import com.mindease.backend.features.physical.dto.DeviceResponse;
import com.mindease.backend.features.physical.dto.PhysicalTodayResponse;
import com.mindease.backend.features.physical.dto.SyncResponse;
import com.mindease.backend.security.AuthRateLimitFilter;
import com.mindease.backend.security.InternalApiKeyFilter;
import com.mindease.backend.security.JwtAuthenticationFilter;
import com.mindease.backend.security.JwtService;
import com.mindease.backend.security.RateLimiterService;
import com.mindease.backend.security.RestAccessDeniedHandler;
import com.mindease.backend.security.RestAuthenticationEntryPoint;

import io.jsonwebtoken.JwtException;

/**
 * Security contract for the Physical Wellness endpoints: unauthenticated and
 * forged-token requests are rejected, identity comes from the JWT (never from
 * the payload), and cross-user device access resolves to 404.
 */
@WebMvcTest({WearableController.class, PhysicalWellnessController.class})
@Import({
        SecurityConfig.class,
        JwtAuthenticationFilter.class,
        AuthRateLimitFilter.class,
        InternalApiKeyFilter.class,
        RestAuthenticationEntryPoint.class,
        RestAccessDeniedHandler.class,
        RateLimiterService.class
})
class PhysicalWellnessSecurityTest {

    /** Real AppProperties (binding source absent in a slice test). */
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
    private WearableDeviceService deviceService;

    @MockBean
    private PhysicalSyncService syncService;

    @MockBean
    private PhysicalWellnessService wellnessService;

    @MockBean
    private JwtService jwtService;

    @BeforeEach
    void stubTokens() {
        when(jwtService.validateAccessToken("good-token")).thenReturn("user-1");
        when(jwtService.validateAccessToken("bad-token")).thenThrow(new JwtException("bad"));
    }

    // ──────────────────────────────────────── authentication

    @Test
    void today_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(get("/api/v1/physical/today")).andExpect(status().isUnauthorized());
    }

    @Test
    void today_withForgedToken_isUnauthorized() throws Exception {
        mvc.perform(get("/api/v1/physical/today")
                        .header("Authorization", "Bearer bad-token"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void registerDevice_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/wearables")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(deviceBody(null)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void sync_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/physical/sync")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(syncBody(null)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void deleteDevice_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(delete("/api/v1/wearables/device-1"))
                .andExpect(status().isUnauthorized());
    }

    // ──────────────────────────────────────── identity handling

    @Test
    void today_usesJwtIdentity_evenIfPayloadSmugglesUserId() throws Exception {
        when(wellnessService.today("user-1")).thenReturn(todayBlock());

        mvc.perform(get("/api/v1/physical/today")
                        .header("Authorization", "Bearer good-token")
                        .queryParam("userId", "victim-user"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.date").value("2026-10-06"));

        verify(wellnessService).today("user-1");
    }

    @Test
    void registerDevice_carriesAuthenticatedUserOnly() throws Exception {
        when(deviceService.register(eq("user-1"), any())).thenReturn(device("device-1"));

        mvc.perform(post("/api/v1/wearables")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(deviceBody("victim-user")))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").value("device-1"));

        verify(deviceService).register(eq("user-1"), any());
    }

    @Test
    void getForeignDevice_resolvesTo404_not403() throws Exception {
        when(deviceService.get("user-1", "foreign-device"))
                .thenThrow(ApiException.notFound("Wearable device not found"));

        mvc.perform(get("/api/v1/wearables/foreign-device")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isNotFound());
    }

    @Test
    void sync_rejectsMissingRequiredFields() throws Exception {
        mvc.perform(post("/api/v1/physical/sync")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void sync_unknownProviderPattern_isRejected() throws Exception {
        // deviceId/clientSyncId present but metric list malformed → validation.
        String body = """
                {"clientSyncId":"s1","deviceId":"d1","readings":[
                  {"metricType":"MAGIC","value":"not-a-number"}]}
                """;
        mvc.perform(post("/api/v1/physical/sync")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isBadRequest());
    }

    @Test
    void sync_validBatch_returnsAcceptedCounts() throws Exception {
        when(syncService.sync(eq("user-1"), any())).thenReturn(new SyncResponse(
                "session-1", SyncStatus.SUCCESS, 3, 3, 0, 0, List.of(), Instant.now()));

        mvc.perform(post("/api/v1/physical/sync")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(syncBody(null)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("SUCCESS"))
                .andExpect(jsonPath("$.data.accepted").value(3));

        verify(syncService).sync(eq("user-1"), any());
    }

    @Test
    void registerDevice_invalidBattery_isBadRequest() throws Exception {
        mvc.perform(post("/api/v1/wearables")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"provider":"FITPRO","deviceIdentifier":"AA:BB",
                                 "batteryLevel":150}
                                """))
                .andExpect(status().isBadRequest());
    }

    // ──────────────────────────────────────── payload helpers

    private String deviceBody(String smuggledUserId) {
        try {
            Map<String, Object> body = new java.util.LinkedHashMap<>();
            body.put("provider", "FITPRO");
            body.put("deviceIdentifier", "AA:BB:CC:DD:EE:FF");
            body.put("manufacturer", "FitPro");
            body.put("model", "Watch 8");
            body.put("firmwareVersion", "V15183");
            body.put("batteryLevel", 82);
            if (smuggledUserId != null) {
                body.put("userId", smuggledUserId);
            }
            return mapper.writeValueAsString(body);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private String syncBody(String smuggledUserId) {
        try {
            Map<String, Object> body = new java.util.LinkedHashMap<>();
            body.put("clientSyncId", "sync-1");
            body.put("deviceId", "device-1");
            body.put("readings", List.of(Map.of(
                    "metricType", "STEPS",
                    "value", 6842,
                    "unit", "steps",
                    "timestamp", Instant.now().toString())));
            if (smuggledUserId != null) {
                body.put("userId", smuggledUserId);
            }
            return mapper.writeValueAsString(body);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private DeviceResponse device(String id) {
        return new DeviceResponse(id, null, "FitPro", "Watch 8", "V15183",
                "AA:BB:CC:DD:EE:FF", List.of("STEPS"), null, 82, false,
                null, null, null, Instant.now(), Instant.now());
    }

    private PhysicalTodayResponse todayBlock() {
        return new PhysicalTodayResponse(
                java.time.LocalDate.of(2026, 10, 6),
                null,
                new PhysicalTodayResponse.MetricBlock(true, 6842d, "steps", Instant.now()),
                PhysicalTodayResponse.MetricBlock.noData("m"),
                PhysicalTodayResponse.MetricBlock.unsupported("kcal"),
                new PhysicalTodayResponse.HeartRateBlock(true, 72d, 74d, null, "bpm",
                        Instant.now()),
                new PhysicalTodayResponse.SleepBlock(true, 25_920_000L,
                        Instant.now().minusSeconds(28_800), Instant.now().minusSeconds(2_880),
                        java.time.LocalDate.of(2026, 10, 6), Instant.now(), null, null),
                new PhysicalTodayResponse.ExerciseBlock(true, 2_520_000L, 1, Instant.now()),
                PhysicalTodayResponse.MetricBlock.noData("min"),
                PhysicalTodayResponse.MetricBlock.unsupported("%"),
                PhysicalTodayResponse.MetricBlock.unsupported("ms"),
                new PhysicalTodayResponse.SyncBlock(Instant.now(), Instant.now(),
                        SyncStatus.SUCCESS, null));
    }
}
