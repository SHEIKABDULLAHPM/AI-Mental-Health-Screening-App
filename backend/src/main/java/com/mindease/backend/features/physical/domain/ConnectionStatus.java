package com.mindease.backend.features.physical.domain;

/**
 * Last known connectivity state of a registered wearable device, as reported
 * by the client sync layer.
 */
public enum ConnectionStatus {

    CONNECTED,
    DISCONNECTED,
    SYNCING,
    UNAVAILABLE,
    UNKNOWN
}
