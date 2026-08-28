package com.mindease.backend.screening.domain;

/**
 * Fixed questionnaire layout mirrored from the Flutter UI. The server validates
 * every response against these constraints so the backend stays the final
 * validation layer.
 */
public enum Questionnaire {

    PHQ9("phq9", 9, 0, 3),
    GAD7("gad7", 7, 0, 3),
    PSS10("pss10", 10, 0, 4),
    WHO5("who5", 5, 0, 5);

    private final String code;
    private final int items;
    private final int min;
    private final int max;

    Questionnaire(String code, int items, int min, int max) {
        this.code = code;
        this.items = items;
        this.min = min;
        this.max = max;
    }

    public String code() {
        return code;
    }

    public int items() {
        return items;
    }

    public int min() {
        return min;
    }

    public int max() {
        return max;
    }

    public static Questionnaire byCode(String code) {
        for (Questionnaire q : values()) {
            if (q.code.equalsIgnoreCase(code)) {
                return q;
            }
        }
        return null;
    }
}