package com.mindease.backend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

/**
 * MindEase backend entry point.
 */
@SpringBootApplication
@EnableAsync
public class MindEaseApplication {

    public static void main(String[] args) {
        SpringApplication.run(MindEaseApplication.class, args);
    }
}