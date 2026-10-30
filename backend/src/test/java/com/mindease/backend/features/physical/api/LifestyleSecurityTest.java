package com.mindease.backend.features.physical.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.LocalDate;
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
import com.mindease.backend.config.AppProperties;
import com.mindease.backend.config.SecurityConfig;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.features.physical.application.BodyMeasurementService;
import com.mindease.backend.features.physical.application.DeviceCapabilityService;
import com.mindease.backend.features.physical.application.HydrationService;
import com.mindease.backend.features.physical.application.PhysicalInsightService;
import com.mindease.backend.features.physical.application.PhysicalTrendService;
import com.mindease.backend.features.physical.application.WellnessGoalService;
import com.mindease.backend.features.physical.dto.BodyMeasurementDtos;
import com.mindease.backend.features.physical.dto.HydrationDtos;
import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.features.physical.dto.TrendDtos;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.security.AuthRateLimitFilter;
import com.mindease.backend.security.InternalApiKeyFilter;
import com.mindease.backend.security.JwtAuthenticationFilter;
import com.mindease.backend.security.JwtService;
import com.mindease.backend.security.RateLimiterService;
import com.mindease.backend.security.RestAccessDeniedHandler;
import com.mindease.backend.security.RestAuthenticationEntryPoint;

import io.jsonwebtoken.JwtException;

/**
 * Security contract for the Phase 2–4 endpoints. Every mutation resolves the
 * user from the JWT, cross-user ids surface as 404, and unauthenticated calls
 * never reach the service layer.
 */
@WebMvcTest({HydrationController.class, BodyMeasurementController.class,
        WellnessGoalController.class, PhysicalTrendController.class,
        PhysicalInsightController.class, DeviceCapabilityController.class})
@Import({
        SecurityConfig.class,
        JwtAuthenticationFilter.class,
        AuthRateLimitFilter.class,
        InternalApiKeyFilter.class,
        RestAuthenticationEntryPoint.class,
        RestAccessDeniedHandler.class,
        RateLimiterService.class
})
class LifestyleSecurityTest {

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
    private HydrationService hydrationService;
    @MockBean
    private BodyMeasurementService bodyService;
    @MockBean
    private WellnessGoalService goalService;
    @MockBean
    private PhysicalTrendService trendService;
    @MockBean
    private PhysicalInsightService insightService;
    @MockBean
    private DeviceCapabilityService capabilityService;
    @MockBean
    private JwtService jwtService;

    @BeforeEach
    void stubTokens() {
        when(jwtService.validateAccessToken("good-token")).thenReturn("user-1");
        when(jwtService.validateAccessToken("bad-token")).thenThrow(new JwtException("bad"));
    }

    private HydrationDtos.HydrationResponse hydrationResponse() {
        return new HydrationDtos.HydrationResponse(
                "ml", 2000, false,
                new HydrationDtos.DayResponse(LocalDate.of(2026, 10, 25), 500d, 1,
                        List.of(new HydrationDtos.EntryResponse("e1",
                                LocalDate.of(2026, 10, 25), 500d, Instant.now(),
                                "USER_ENTERED"))),
                List.of(), "guidance");
    }

    // ── authentication ─────────────────────────────────────────────────────

    @Test
    void hydration_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(get("/api/v1/physical/hydration")).andExpect(status().isUnauthorized());
    }

    @Test
    void hydration_withForgedToken_isUnauthorized() throws Exception {
        mvc.perform(get("/api/v1/physical/hydration")
                        .header("Authorization", "Bearer bad-token"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void insights_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(get("/api/v1/physical/insights")).andExpect(status().isUnauthorized());
    }

    @Test
    void capabilities_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(get("/api/v1/wearables/device-1/capabilities"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void hydrationPost_withoutToken_isUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/physical/hydration")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":250}"))
                .andExpect(status().isUnauthorized());
    }

    // ── identity from the token, never the payload ─────────────────────────

    @Test
    void hydration_usesJwtIdentity_evenIfPayloadSmugglesUserId() throws Exception {
        when(hydrationService.add(eq("user-1"), any())).thenReturn(
                new HydrationDtos.EntryResponse("e1", LocalDate.of(2026, 10, 25),
                        250d, Instant.now(), "USER_ENTERED"));

        mvc.perform(post("/api/v1/physical/hydration")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(mapper.writeValueAsString(Map.of(
                                "amount", 250,
                                "unit", "ml",
                                "userId", "victim-user"))))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.amountMl").value(250));

        verify(hydrationService).add(eq("user-1"), any());
    }

    @Test
    void hydrationDelete_forwardsOnlyAuthenticatedUser() throws Exception {
        mvc.perform(delete("/api/v1/physical/hydration/e1")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isOk());

        verify(hydrationService).delete("user-1", "e1");
    }

    @Test
    void hydrationDelete_ofForeignEntry_is404() throws Exception {
        org.mockito.Mockito.doThrow(ApiException.notFound("Hydration entry not found"))
                .when(hydrationService).delete("user-1", "foreign");

        mvc.perform(delete("/api/v1/physical/hydration/foreign")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isNotFound());
    }

    @Test
    void bodyMeasurement_usesJwtIdentity() throws Exception {
        when(bodyService.add(eq("user-1"), any())).thenReturn(
                new BodyMeasurementDtos.MeasurementResponse("m1",
                        LocalDate.of(2026, 10, 25), 70d, null, Instant.now(),
                        "USER_ENTERED", null));

        mvc.perform(post("/api/v1/physical/body")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(mapper.writeValueAsString(Map.of(
                                "weight", 70,
                                "weightUnit", "kg",
                                "userId", "victim-user"))))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.weightKg").value(70));

        verify(bodyService).add(eq("user-1"), any());
    }

    @Test
    void goalsUpdate_usesJwtIdentity() throws Exception {
        when(goalService.update(eq("user-1"), any())).thenReturn(
                new WellnessGoalDtos.GoalsResponse(
                        new WellnessGoalDtos.GoalTargets(8000, null, null, null, null),
                        true, List.of(), Map.of(),
                        new WellnessGoalDtos.GoalTargets(7000, 30, 120, 480, 2000),
                        List.of("guidance")));

        mvc.perform(put("/api/v1/physical/goals")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dailySteps\":8000}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.goals.dailySteps").value(8000));

        verify(goalService).update(eq("user-1"), any());
    }

    // ── validation ─────────────────────────────────────────────────────────

    @Test
    void hydration_rejectsOversizedEntry() throws Exception {
        mvc.perform(post("/api/v1/physical/hydration")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":9000,\"unit\":\"ml\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void goals_rejectUnsafeTargets() throws Exception {
        mvc.perform(put("/api/v1/physical/goals")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dailyHydrationMl\":50000}"))
                .andExpect(status().isBadRequest());
        mvc.perform(put("/api/v1/physical/goals")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"dailySleepMinutes\":30}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void capabilityReport_rejectsUnknownMetric() throws Exception {
        when(capabilityService.report(eq("user-1"), eq("device-1"), any()))
                .thenThrow(ApiException.badRequest("Unknown capability: MAGIC"));

        mvc.perform(put("/api/v1/wearables/device-1/capabilities")
                        .header("Authorization", "Bearer good-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"capabilities\":[{\"metric\":\"MAGIC\","
                                + "\"supportStatus\":\"SUPPORTED_UNVERIFIED\"}]}"))
                .andExpect(status().isBadRequest());
    }

    // ── successful reads ───────────────────────────────────────────────────

    @Test
    void hydrationOverview_returnsEnvelope() throws Exception {
        when(hydrationService.overview("user-1", 7)).thenReturn(hydrationResponse());

        mvc.perform(get("/api/v1/physical/hydration")
                        .header("Authorization", "Bearer good-token")
                        .queryParam("days", "7"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.targetMl").value(2000))
                .andExpect(jsonPath("$.data.today.totalMl").value(500));
    }

    @Test
    void trends_and_insights_returnEnvelopes() throws Exception {
        when(trendService.trends("user-1", null)).thenReturn(new TrendDtos.TrendsResponse(
                LocalDate.of(2026, 10, 19), LocalDate.of(2026, 10, 25), 7, 7,
                List.of(), List.of("Steps: no data in this window.")));
        when(insightService.insights("user-1")).thenReturn(new InsightDtos.InsightsResponse(
                Instant.now(), 14, false, List.of(), List.of(), false,
                new InsightDtos.DataCoverage(14, 0, 0, 0, 0, 0, List.of("STEPS")),
                List.of("Data is stale."), "not medical advice"));

        mvc.perform(get("/api/v1/physical/trends")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.windowDays").value(7));
        mvc.perform(get("/api/v1/physical/insights")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.sufficientData").value(false));
    }

    @Test
    void capabilityGet_scopesToAuthenticatedUser() throws Exception {
        when(capabilityService.list("user-1", "device-1"))
                .thenReturn(new com.mindease.backend.features.physical.dto
                        .DeviceCapabilityDtos.CapabilityListResponse(
                                "device-1", "Watch 8", "V15183", List.of(),
                                List.of("No capability has been verified")));

        mvc.perform(get("/api/v1/wearables/device-1/capabilities")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.deviceId").value("device-1"));

        verify(capabilityService).list("user-1", "device-1");
    }

    @Test
    void capabilityGet_ofForeignDevice_is404() throws Exception {
        when(capabilityService.list("user-1", "foreign"))
                .thenThrow(ApiException.notFound("Wearable device not found"));

        mvc.perform(get("/api/v1/wearables/foreign/capabilities")
                        .header("Authorization", "Bearer good-token"))
                .andExpect(status().isNotFound());
    }
}
