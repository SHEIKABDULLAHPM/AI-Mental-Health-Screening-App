package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpEntity;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.features.physical.dto.InsightDtos;

/**
 * The AI boundary is also a privacy boundary. Only aggregated, non-identifying
 * context may leave the backend, and any failure must resolve to "AI
 * unavailable" rather than an exception.
 */
@ExtendWith(MockitoExtension.class)
class PhysicalInsightAiClientTest {

    @Mock
    private RestTemplate restTemplate;

    private PhysicalInsightAiClient client;

    @BeforeEach
    void setUp() {
        client = new PhysicalInsightAiClient(restTemplate,
                "http://ai-service:8000/api/v1", "internal-key");
    }

    private InsightDtos.DataCoverage coverage() {
        return new InsightDtos.DataCoverage(14, 10, 8, 5, 6, 4, List.of("SPO2"));
    }

    private MindBodyPatternEngine.Result result(boolean sufficient) {
        List<InsightDtos.PatternInsight> insights = sufficient
                ? List.of(new InsightDtos.PatternInsight(
                        "sleep_below_baseline", "Sleep shorter than baseline",
                        "Narrative", "ATTENTION", "MEDIUM", List.of(), coverage(),
                        MindBodyPatternEngine.DISCLAIMER))
                : List.of(new InsightDtos.PatternInsight(
                        "insufficient_recent_data", "No data", "Narrative", "INFO", "LOW",
                        List.of(), coverage(), MindBodyPatternEngine.DISCLAIMER));
        return new MindBodyPatternEngine.Result(insights, List.of(), coverage(), sufficient,
                List.of());
    }

    private MindBodyPatternEngine.WellnessContext context() {
        return new MindBodyPatternEngine.WellnessContext(
                LocalDate.of(2026, 10, 25), 14, List.of(), List.of(), Map.of(), List.of(),
                Map.of(), Map.of(), 2000, 480);
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void suggest_sendsOnlyAggregatedContext() {
        Map<String, Object> body = Map.of(
                "recommendations", List.of(Map.of(
                        "id", "walk",
                        "title", "Walk",
                        "description", "Gentle walk",
                        "category", "ACTIVITY")),
                "note", "AI note");
        when(restTemplate.postForEntity(anyString(), any(), eq(Map.class)))
                .thenReturn(ResponseEntity.ok((Map) body));

        var outcome = client.suggest(context(), result(true));

        ArgumentCaptor<Object> payload = ArgumentCaptor.forClass(Object.class);
        org.mockito.Mockito.verify(restTemplate)
                .postForEntity(anyString(), payload.capture(), eq(Map.class));

        HttpEntity<?> entity = (HttpEntity<?>) payload.getValue();
        @SuppressWarnings("unchecked")
        Map<String, Object> sent = (Map<String, Object>) entity.getBody();
        assertThat(sent).containsKeys("window_days", "coverage", "patterns",
                "goals", "existing_recommendations");
        // No identifiers, timestamps or free text may cross the boundary.
        assertThat(sent).doesNotContainKeys("userId", "deviceId", "readings", "journal",
                "checkinNotes", "weight");
        assertThat(entity.getHeaders().getFirst("X-Internal-API-Key"))
                .isEqualTo("internal-key");
        assertThat(outcome.available()).isTrue();
        assertThat(outcome.recommendations()).hasSize(1);
        assertThat(outcome.recommendations().get(0).id()).isEqualTo("ai_walk");
        assertThat(outcome.note()).isEqualTo("AI note");
    }

    @Test
    void suggest_isSkippedWhenDataIsInsufficient() {
        var outcome = client.suggest(context(), result(false));

        assertThat(outcome.available()).isFalse();
        verifyNoInteractions(restTemplate);
    }

    @Test
    void suggest_returnsUnavailableOnTransportFailure() {
        when(restTemplate.postForEntity(anyString(), any(), eq(Map.class)))
                .thenThrow(new RestClientException("connection refused"));

        var outcome = client.suggest(context(), result(true));

        assertThat(outcome.available()).isFalse();
        assertThat(outcome.recommendations()).isEmpty();
    }

    @Test
    void suggest_ignoresMalformedRecommendations() {
        Map<String, Object> body = Map.of(
                "recommendations", List.of(
                        Map.of("id", "missing-fields"),
                        "not-a-map"),
                "note", "note");
        when(restTemplate.postForEntity(anyString(), any(), eq(Map.class)))
                .thenReturn(ResponseEntity.ok(body));

        var outcome = client.suggest(context(), result(true));

        assertThat(outcome.available()).isTrue();
        assertThat(outcome.recommendations()).isEmpty();
    }

    @Test
    void suggest_capsAiRecommendationsAtThree() {
        Map<String, Object> rec = Map.of(
                "id", "r",
                "title", "T",
                "description", "D",
                "category", "C");
        Map<String, Object> body = Map.of("recommendations",
                List.of(rec, rec, rec, rec, rec));
        when(restTemplate.postForEntity(anyString(), any(), eq(Map.class)))
                .thenReturn(ResponseEntity.ok(body));

        var outcome = client.suggest(context(), result(true));

        assertThat(outcome.recommendations()).hasSize(3);
    }
}
