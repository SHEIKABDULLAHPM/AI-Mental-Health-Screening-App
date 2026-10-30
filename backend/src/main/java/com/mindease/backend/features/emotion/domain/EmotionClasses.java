package com.mindease.backend.features.emotion.domain;

import java.util.Set;

/**
 * Canonical facial-emotion vocabulary, shared by the wire contract, the
 * service-level score validation and the tests.
 *
 * <p>Single source of truth on purpose. The on-device model is
 * {@code vit-fer-7} (ViT-B/16, fp16) and its class order is the model's own
 * {@code id2label}. Previously this was the 8-class synora-fer vocabulary
 * ({@code contempt}, {@code happiness}, {@code sadness}), which the ViT no
 * longer emits — leaving these names in place rejected every camera event
 * with a 400. The Flutter client, the Python AI service and this backend
 * must all agree on this exact set.
 */
public final class EmotionClasses {

    private EmotionClasses() {
    }

    /**
     * The seven model classes, in the model's own output order:
     * anger, disgust, fear, happy, neutral, sad, surprise.
     */
    public static final Set<String> CANONICAL = Set.of(
            "anger", "disgust", "fear", "happy", "neutral", "sad", "surprise");

    /** Wire value used when there is no trustworthy prediction. */
    public static final String UNKNOWN = "unknown";

    /** Regex fragment matching a canonical class or {@link #UNKNOWN}. */
    public static final String PATTERN =
            "anger|disgust|fear|happy|neutral|sad|surprise|" + UNKNOWN;

    /**
     * Number of classes every {@code scores} map must carry.
     *
     * <p>Declared as a literal because it is consumed by an annotation
     * ({@code @Size}), which requires a compile-time constant —
     * {@code CANONICAL.size()} would not qualify.
     */
    public static final int COUNT = 7;
}
