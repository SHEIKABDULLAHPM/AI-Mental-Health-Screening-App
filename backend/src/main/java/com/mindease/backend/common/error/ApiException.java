package com.mindease.backend.common.error;

import lombok.Getter;
import org.springframework.http.HttpStatus;

/**
 * Base business/technical exception carrying a stable error code.
 */
@Getter
public class ApiException extends RuntimeException {

    private final ErrorCode code;
    private final HttpStatus status;
    private final String codeName;

    public ApiException(ErrorCode code, String message) {
        super(message);
        this.code = code;
        this.status = code.status();
        this.codeName = code.name();
    }

    public static ApiException notFound(String message) {
        return new ApiException(ErrorCode.NOT_FOUND, message);
    }

    public static ApiException badRequest(String message) {
        return new ApiException(ErrorCode.BAD_REQUEST, message);
    }

    public static ApiException internal(String message) {
        return new ApiException(ErrorCode.INTERNAL_ERROR, message);
    }
}