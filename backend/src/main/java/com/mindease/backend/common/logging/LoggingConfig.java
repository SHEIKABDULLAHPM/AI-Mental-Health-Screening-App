package com.mindease.backend.common.logging;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * Lightweight access logging for every HTTP request.
 */
@Configuration
public class LoggingConfig {

    private static final Logger audit = LoggerFactory.getLogger("AUDIT");

    @Bean
    public FilterRegistrationBean<Filter> accessLogFilter() {
        FilterRegistrationBean<Filter> reg = new FilterRegistrationBean<>();
        reg.setFilter((ServletRequest req, ServletResponse res, FilterChain chain) -> {
            long start = System.nanoTime();
            chain.doFilter(req, res);
            long elapsedMs = (System.nanoTime() - start) / 1_000_000;
            if (req instanceof HttpServletRequest httpReq && res instanceof HttpServletResponse httpRes) {
                audit.info("{} {} -> {} ({}ms) from {}",
                        httpReq.getMethod(),
                        sanitize(httpReq.getRequestURI()),
                        httpRes.getStatus(),
                        elapsedMs,
                        httpReq.getRemoteAddr());
            } else {
                chain.doFilter(req, res);
            }
        });
        reg.setName("accessLogFilter");
        reg.addUrlPatterns("/api/*");
        reg.setOrder(Ordered.LOWEST_PRECEDENCE);
        return reg;
    }

    private static String sanitize(String uri) {
        // Avoid logging query strings that could carry tokens.
        int q = uri.indexOf('?');
        return q > 0 ? uri.substring(0, q) : uri;
    }
}