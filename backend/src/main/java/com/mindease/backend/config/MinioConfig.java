package com.mindease.backend.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import io.minio.MinioClient;

/**
 * MinIO S3-compatible object storage client.
 */
@Configuration
public class MinioConfig {

    @Value("${mindease.minio.url}")
    private String url;

    @Value("${mindease.minio.access-key}")
    private String accessKey;

    @Value("${mindease.minio.secret-key}")
    private String secretKey;

    @Value("${mindease.minio.bucket}")
    private String bucket;

    @Bean
    public MinioClient minioClient() {
        return MinioClient.builder()
                .endpoint(url)
                .credentials(accessKey, secretKey)
                .build();
    }

    @Bean
    public String minioBucket() {
        return bucket;
    }
}