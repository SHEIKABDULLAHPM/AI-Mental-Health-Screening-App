package com.mindease.backend.config;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

/**
 * Outbound HTTP client used to call the AI service and other REST endpoints.
 */
@Configuration
public class ApiClientConfig {

    @Value("${mindease.ai.connect-timeout:5s}")
    private Duration connectTimeout;

    @Value("${mindease.ai.read-timeout:60s}")
    private Duration readTimeout;

    @Bean
    public RestTemplate restTemplate(RestTemplateBuilder builder) {
        return builder
                .setConnectTimeout(connectTimeout)
                .setReadTimeout(readTimeout)
                .build();
    }
}