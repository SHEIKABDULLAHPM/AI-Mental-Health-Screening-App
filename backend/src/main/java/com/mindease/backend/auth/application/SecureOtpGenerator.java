package com.mindease.backend.auth.application;

import org.springframework.stereotype.Component;

import com.mindease.backend.common.security.Tokens;

/** Cryptographically random numeric OTP generator. */
@Component
public class SecureOtpGenerator implements OtpGenerator {

    @Override
    public String generate(int length) {
        return Tokens.randomNumeric(length);
    }
}