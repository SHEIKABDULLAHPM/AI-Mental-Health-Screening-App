package com.mindease.backend.common.client;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;

/**
 * Thin HTTP client to the MindEase AI service.
 * Used for screening analysis, emotion detection, risk assessment and
 * recommendations once those modules are wired.
 */
@Component
public class AiServiceClient {

    private static final Logger log = LoggerFactory.getLogger(AiServiceClient.class);

    private final RestTemplate restTemplate;
    private final String baseUrl;

    public AiServiceClient(RestTemplate restTemplate,
                           @Value("${mindease.ai.base-url}") String baseUrl) {
        this.restTemplate = restTemplate;
        this.baseUrl = baseUrl;
    }

    public String analyze(String endpoint, Object payload) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<Object> request = new HttpEntity<>(payload, headers);
        try {
            String url = baseUrl + endpoint;
            log.debug("Calling AI service at {}", url);
            return restTemplate.postForObject(url, request, String.class);
        } catch (RestClientException ex) {
            log.error("AI service call failed: {}", ex.getMessage());
            throw new ApiException(ErrorCode.UPSTREAM_UNAVAILABLE, "AI service temporarily unavailable");
        }
    }

    public Map<?, ?> health() {
        try {
            return restTemplate.getForObject(baseUrl + "/health", Map.class);
        } catch (RestClientException ex) {
            log.warn("AI service unreachable: {}", ex.getMessage());
            return Map.of("status", "DOWN");
        }
    }
}