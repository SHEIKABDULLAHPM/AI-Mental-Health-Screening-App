package com.mindease.backend.config;

import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.mindease.backend.config.AppProperties.Ai;

/**
 * RabbitMQ wiring for the asynchronous AI job pipeline. The backend publishes
 * {@code {jobId}} messages onto the durable {@code ai_tasks} queue; the Python
 * AI service consumes them.
 */
@Configuration
public class RabbitConfig {

    private final Ai ai;

    public RabbitConfig(AppProperties properties) {
        this.ai = properties.getAi();
    }

    @Bean
    public Queue aiTasksQueue() {
        return new Queue(ai.getTasksQueue(), true);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setRoutingKey(ai.getTasksQueue());
        return template;
    }
}
