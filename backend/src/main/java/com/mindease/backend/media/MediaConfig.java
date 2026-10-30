package com.mindease.backend.media;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

import java.net.URI;

@Configuration
public class MediaConfig {

    @Value("${mindease.media.url:http://minio:9090}")
    private String endpointUrl;

    /**
     * Client-reachable MinIO address used only for presigned download URLs.
     * The upload client continues to use the internal Docker hostname above.
     */
    @Value("${mindease.media.public-url:}")
    private String publicEndpointUrl;

    @Value("${mindease.media.access-key:mindease}")
    private String accessKey;

    @Value("${mindease.media.secret-key:change-me-dev-minio}")
    private String secretKey;

    @Value("${mindease.media.bucket:mindease-files}")
    private String bucket;

    @Bean
    public S3Client s3Client() {
        return S3Client.builder()
                .endpointOverride(URI.create(endpointUrl))
                .region(Region.US_EAST_1)
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(accessKey, secretKey)))
                .forcePathStyle(true)
                .build();
    }

    @Bean
    public S3Presigner s3Presigner() {
        return S3Presigner.builder()
                .endpointOverride(URI.create(
                        publicEndpointUrl == null || publicEndpointUrl.isBlank()
                                ? endpointUrl
                                : publicEndpointUrl))
                .region(Region.US_EAST_1)
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create(accessKey, secretKey)))
                .build();
    }

    public String getBucket() {
        return bucket;
    }
}
