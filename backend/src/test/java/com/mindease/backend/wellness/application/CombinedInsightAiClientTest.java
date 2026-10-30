package com.mindease.backend.wellness.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.features.physical.dto.InsightDtos;
import com.mindease.backend.wellness.domain.ProfileStatus;
import com.mindease.backend.wellness.dto.WellnessProfileDto;

/**
 * Contract of the outbound combined-insight call.
 *
 * <p>Only deterministic aggregates may leave the backend. A stored mood label
 * has no observation timestamp here, and sending it previously produced
 * unsupported recency claims ("you are feeling happy today"), so its absence is
 * pinned by this test.</p>
 */
class CombinedInsightAiClientTest {

    private WellnessProfileDto profile() {
        return new WellnessProfileDto(
                "profile-1", "assessment-1", ProfileStatus.COMPLETED,
                54, "LOW", 64, "FAIR", "MOOD_SUPPORT",
                "stored insight", "happy", "joy", 3, 8,
                "stable", "steady", 4,
                null, null, null,
                true, Instant.now(), Instant.now());
    }

    private InsightDtos.InsightsResponse physical() {
        return new InsightDtos.InsightsResponse(
                Instant.now(), 14, false, List.of(), List.of(), false,
                new InsightDtos.DataCoverage(14, 2, 0, 2, 1, 0, List.of("SLEEP")),
                List.of(), "not medical advice");
    }

    @Test
    void sendsOnlyAggregatesAndNeverTheUntimestampedMoodLabel() {
        RestTemplate restTemplate = new RestTemplate();
        MockRestServiceServer server = MockRestServiceServer.bindTo(restTemplate).build();
        server.expect(requestTo("http://ai.test/api/v1/wellness/combined-insight"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(jsonPath("$.mental.wellness_score").value(54))
                .andExpect(jsonPath("$.mental.safety_flag").value(true))
                .andExpect(jsonPath("$.mental.mood").doesNotExist())
                .andExpect(jsonPath("$.mental.mood_trend").doesNotExist())
                .andExpect(jsonPath("$.physical.coverage.activity_days").value(2))
                .andExpect(jsonPath("$.physical.coverage.sleep_days").value(0))
                .andExpect(jsonPath("$.physical.pattern_ids").isArray())
                .andRespond(withSuccess(
                        "{\"narrative\":\"Your stored check-in and recent aggregates "
                                + "suggest keeping a steady routine.\","
                                + "\"suggestions\":[],\"generated_by\":\"rules\"}",
                        MediaType.APPLICATION_JSON));

        var client = new CombinedInsightAiClient(restTemplate,
                "http://ai.test/api/v1", "shared-key");

        var result = client.generate(profile(), physical());

        assertThat(result.available()).isTrue();
        assertThat(result.generatedBy()).isEqualTo("rules");
        server.verify();
    }
}
