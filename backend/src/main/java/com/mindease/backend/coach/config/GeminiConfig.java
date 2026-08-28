package com.mindease.backend.coach.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

/**
 * Configuration for the Gemini API client.
 * The API key is injected from environment variables and NEVER logged.
 */
@Configuration
public class GeminiConfig {

    @Bean(name = "geminiRestTemplate")
    public RestTemplate geminiRestTemplate(
            @Value("${mindease.gemini.timeout-seconds:30}") int timeoutSeconds) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5000); // 5s connect
        factory.setReadTimeout(timeoutSeconds * 1000); // configurable read timeout
        return new RestTemplate(factory);
    }
}
