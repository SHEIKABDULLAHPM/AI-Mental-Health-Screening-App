package com.mindease.backend.features.physical.domain;

/**
 * Identifies the source system a wearable device or health record came from.
 * The physical wellness domain depends only on this abstraction, so additional
 * providers (Health Connect, Samsung Health, Wear OS, ...) can be added later
 * without touching dashboards, aggregation or AI context building.
 */
public enum WearableProvider {

    /** FitPro-family proprietary BLE devices (FitPro Watch 8, firmware V15183). */
    FITPRO,

    /** Google Health Connect (added in a later phase). */
    HEALTH_CONNECT,

    /** Samsung Health (added in a later phase). */
    SAMSUNG_HEALTH,

    /** Wear OS (added in a later phase). */
    WEAR_OS,

    /** Data entered directly by the user (no device involved). */
    MANUAL
}
