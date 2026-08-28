package com.mindease.backend.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mindease.backend.config.AppProperties;

/**
 * Verifies the internal callback endpoints are only reachable with the shared
 * internal API key - the front-line defense a compromised AI-service client
 * would face when trying to inject fabricated insights.
 */
class InternalApiKeyFilterTest {

    private final AppProperties props = new AppProperties();
    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();
    private final InternalApiKeyFilter filter =
            new InternalApiKeyFilter(props, mapper);

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void allowsRequestWithCorrectKey() throws Exception {
        props.getAi().setInternalApiKey("secret-key");
        MockHttpServletRequest request = request("/api/v1/internal/ai-analysis/job-1/complete", "secret-key");
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(chain.getRequest()).isNotNull();
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        assertThat(auth.getAuthorities())
                .anyMatch(a -> a.getAuthority().equals("ROLE_INTERNAL"));
    }

    @Test
    void rejectsMissingKey() throws Exception {
        props.getAi().setInternalApiKey("secret-key");
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request("/api/v1/internal/ai-analysis/job-1/claim", null), response, chain);

        assertThat(response.getStatus()).isEqualTo(403);
        assertThat(chain.getRequest()).isNull();
    }

    @Test
    void rejectsWrongKey() throws Exception {
        props.getAi().setInternalApiKey("secret-key");
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request("/api/v1/internal/ai-analysis/job-1/fail", "wrong-key"), response, chain);

        assertThat(response.getStatus()).isEqualTo(403);
        assertThat(chain.getRequest()).isNull();
    }

    @Test
    void doesNotFilterNonInternalRoutes() throws Exception {
        props.getAi().setInternalApiKey("secret-key");
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request("/api/v1/ai-analysis/job-1/status", null), response, chain);

        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(chain.getRequest()).isNotNull();
    }

    private static MockHttpServletRequest request(String uri, String key) {
        MockHttpServletRequest r = new MockHttpServletRequest("POST", uri);
        r.setRequestURI(uri);
        if (key != null) {
            r.addHeader(InternalApiKeyFilter.INTERNAL_HEADER, key);
        }
        return r;
    }
}