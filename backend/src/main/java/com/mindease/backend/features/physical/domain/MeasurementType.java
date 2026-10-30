package com.mindease.backend.features.physical.domain;

/**
 * Provenance of a health measurement. The distinction between device-measured,
 * user-entered, imported, calculated and AI-derived values is always preserved
 * so downstream consumers never treat a self-report as a device reading.
 */
public enum MeasurementType {

    /** Measured by the wearable device itself. */
    DEVICE_MEASURED,

    /** Typed in by the user. */
    USER_ENTERED,

    /** Imported from another health platform (Health Connect, etc.). */
    IMPORTED,

    /** Derived by Synora from other measurements. */
    CALCULATED,

    /** Produced by AI/LLM processing. */
    AI_DERIVED
}
