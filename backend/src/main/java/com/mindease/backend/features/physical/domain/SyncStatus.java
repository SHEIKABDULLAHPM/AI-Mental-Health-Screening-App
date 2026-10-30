package com.mindease.backend.features.physical.domain;

/**
 * Outcome of a synchronization session.
 */
public enum SyncStatus {

    /** Everything in the batch was accepted. */
    SUCCESS,

    /** Some records were accepted, others rejected. */
    PARTIAL,

    /** Nothing was accepted. */
    FAILED,

    /** Session opened but not completed (client crashed / disconnected). */
    IN_PROGRESS
}
