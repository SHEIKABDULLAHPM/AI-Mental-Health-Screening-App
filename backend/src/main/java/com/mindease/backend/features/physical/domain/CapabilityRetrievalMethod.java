package com.mindease.backend.features.physical.domain;

/**
 * How a metric is obtained from a given device/provider. Kept explicit so the
 * UI and the AI context can distinguish a sensor measurement from a value the
 * user typed in.
 */
public enum CapabilityRetrievalMethod {

    /** Standard GATT service/characteristic (battery, device info). */
    GATT_STANDARD,

    /** Vendor-specific BLE protocol (FitPro frames). */
    VENDOR_PROTOCOL,

    /** Imported through Health Connect (not implemented yet). */
    HEALTH_CONNECT,

    /** Typed in by the user. */
    MANUAL_ENTRY,

    /** Derived from other measurements (e.g. BMI from height + weight). */
    CALCULATED,

    /** No retrieval path exists. */
    NONE
}
