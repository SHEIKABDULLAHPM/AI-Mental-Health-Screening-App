package com.mindease.backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Synora backend entry point.
 */
@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class MindEaseApplication {

    public static void main(String[] args) {
        SpringApplication.run(MindEaseApplication.class, args);
    }
}