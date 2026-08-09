package com.mindease.backend.config;

import java.util.HashMap;
import java.util.Map;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * RabbitMQ topology + message converter.
 * Declares the AI-task queue where long-running AI jobs are deferred.
 */
@Configuration
public class RabbitConfig {

    public static final String AI_TASKS_EXCHANGE = "ai.tasks.exchange";
    public static final String AI_TASKS_ROUTING_KEY = "ai.tasks";

    @Value("${mindease.rabbitmq.queue-ai-tasks:ai_tasks}")
    private String aiTasksQueue;

    @Bean
    public DirectExchange aiTasksExchange() {
        return new DirectExchange(AI_TASKS_EXCHANGE, true, false);
    }

    @Bean
    public Queue aiTasksQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-dead-letter-exchange", AI_TASKS_EXCHANGE);
        args.put("x-dead-letter-routing-key", "ai.tasks.dlq");
        return new Queue(aiTasksQueue, true, false, false, args);
    }

    @Bean
    public Binding aiTasksBinding(DirectExchange aiTasksExchange) {
        return BindingBuilder.bind(aiTasksQueue()).to(aiTasksExchange()).with(AI_TASKS_ROUTING_KEY);
    }

    @Bean
    public MessageConverter jsonMessageConverter(ObjectMapper objectMapper) {
        return new Jackson2JsonMessageConverter(objectMapper);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory,
                                         MessageConverter messageConverter) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(messageConverter);
        return template;
    }
}