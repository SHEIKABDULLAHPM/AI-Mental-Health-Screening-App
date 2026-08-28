package com.mindease.backend.auth.application;

/**
 * Produces the numeric one-time password. Injectable so tests can substitute
 * a deterministic generator without changing the verification path.
 */
public interface OtpGenerator {

    String generate(int length);
}