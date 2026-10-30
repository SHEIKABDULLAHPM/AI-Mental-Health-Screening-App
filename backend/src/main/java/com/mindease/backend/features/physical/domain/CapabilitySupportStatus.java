package com.mindease.backend.features.physical.domain;

/**
 * How confidently the platform may claim a device supports a metric.
 *
 * <p>Only {@link #SUPPORTED_VERIFIED} may be presented to the user as a working
 * feature; everything else must be shown with its limitation. Verification can
 * only be granted after an on-device validation pass against the real device —
 * a client can report what it observed, but cannot promote a capability to
 * "verified".</p>
 */
public enum CapabilitySupportStatus {

    /** Exposed and confirmed against real hardware readings. */
    SUPPORTED_VERIFIED,

    /** Exposed by the protocol but not yet confirmed against this firmware. */
    SUPPORTED_UNVERIFIED,

    /** The device/provider does not expose this metric. */
    UNSUPPORTED,

    /** Not yet determined for this device. */
    UNKNOWN,

    /** Usually available but currently failing (e.g. sensor off, permission). */
    TEMPORARILY_UNAVAILABLE
}
