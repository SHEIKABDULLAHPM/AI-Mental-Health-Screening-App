package com.mindease.backend.common.config;

import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * Bounded executor for best-effort side effects (personalization feedback,
 * challenge advancement) that must never block user-facing writes.
 *
 * <p>Small pool with a bounded queue and {@code CallerRunsPolicy}: under
 * extreme overload the caller thread runs the task (degrading to the old
 * synchronous behavior) instead of rejecting it and losing the side effect.
 */
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean(name = "sideEffectExecutor")
    public Executor sideEffectExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(4);
        executor.setQueueCapacity(200);
        executor.setThreadNamePrefix("side-effect-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}
