package com.mindease.backend.screening.application;

import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.screening.domain.Lifestyle;
import com.mindease.backend.screening.domain.MoodAssessment;
import com.mindease.backend.screening.domain.PersonalInfo;
import com.mindease.backend.screening.domain.Questionnaire;
import com.mindease.backend.screening.domain.Screening;

/**
 * Server-side validation of the assessment. The backend is the final
 * validation layer; the Android client can never bypass these checks.
 */
@Component
public class ScreeningValidator {

    public static final int MIN_AGE = 13;
    public static final int MAX_AGE = 120;

    private static final java.util.Set<String> ALLOWED_MOODS = java.util.Set.of(
            "very_happy", "happy", "calm", "okay", "low", "stressed");

    /**
     * Validates a partially completed draft. Any provided value must be within
     * its allowed range, but missing sections are allowed.
     */
    public void validateDraft(Screening screening) {
        // Explicit JSON null sections are treated as absent in drafts (never NPE).
        if (screening.getPersonal() != null) {
            validatePersonal(screening.getPersonal(), false);
        }
        if (screening.getLifestyle() != null) {
            validateLifestyle(screening.getLifestyle(), false);
        }
        if (screening.getAssessments() != null) {
            for (Map.Entry<String, List<Integer>> entry : screening.getAssessments().entrySet()) {
                validateAnswerList(entry.getKey(), entry.getValue(), false);
            }
        }
        if (screening.getMood() != null) {
            validateMood(screening.getMood(), false);
        }
    }

    /**
     * Validates a complete assessment prior to submission: all sections fully
     * answered, every value in range, no unknown question codes.
     */
    public void validateComplete(Screening screening) {
        // A null section can never satisfy a complete assessment (never NPE).
        if (screening.getPersonal() == null) {
            throw invalid("Personal information is required.");
        }
        if (screening.getLifestyle() == null) {
            throw invalid("Lifestyle information is required.");
        }
        if (screening.getAssessments() == null) {
            throw invalid("Assessment answers are required.");
        }
        validatePersonal(screening.getPersonal(), true);
        validateLifestyle(screening.getLifestyle(), true);
        for (Questionnaire questionnaire : Questionnaire.values()) {
            List<Integer> answers = screening.getAssessments().get(questionnaire.code());
            if (answers == null) {
                throw invalid("Missing answers for " + questionnaire.code());
            }
            validateAnswerList(questionnaire.code(), answers, true);
        }
        // Mood stays optional for complete assessments so older clients and
        // pre-integration data keep working; when present it must be valid.
        if (screening.getMood() != null) {
            validateMood(screening.getMood(), true);
        }
    }

    /**
     * Validates the onboarding mood snapshot. Only user-provided values are
     * checked here — scores and trends are always derived server-side and
     * never trusted from the client.
     */
    private void validateMood(MoodAssessment mood, boolean full) {
        if (mood.getCurrentMood() != null && !mood.getCurrentMood().isBlank()) {
            if (!ALLOWED_MOODS.contains(mood.getCurrentMood())) {
                throw invalid("Mood must be one of: very_happy, happy, calm, okay, low, stressed.");
            }
        } else if (full && isPresent(mood)) {
            // A mood section that carries context but no primary mood is
            // incomplete — the self-reported mood is the primary signal.
            throw invalid("Current mood is required when providing a mood assessment.");
        }
        if (mood.getEmotion() != null && mood.getEmotion().length() > 100) {
            throw invalid("Mood emotion must be at most 100 characters.");
        }
        if (mood.getIntensity() != null
                && (mood.getIntensity() < 1 || mood.getIntensity() > 10)) {
            throw invalid("Mood intensity must be between 1 and 10.");
        }
        if (mood.getNote() != null && mood.getNote().length() > 5000) {
            throw invalid("Mood reflection must be at most 5000 characters.");
        }
        if (mood.getFrequency() != null && mood.getFrequency().length() > 40) {
            throw invalid("Mood frequency must be at most 40 characters.");
        }
        if (mood.getRecentChange() != null && mood.getRecentChange().length() > 40) {
            throw invalid("Recent emotional change must be at most 40 characters.");
        }
        if (mood.getContext() != null && mood.getContext().length() > 200) {
            throw invalid("Mood context must be at most 200 characters.");
        }
        if (mood.getLinkedMoodEntryId() != null && mood.getLinkedMoodEntryId().length() > 64) {
            throw invalid("Linked mood entry reference is invalid.");
        }
    }

    private boolean isPresent(MoodAssessment mood) {
        return (mood.getEmotion() != null && !mood.getEmotion().isBlank())
                || mood.getIntensity() != null
                || (mood.getNote() != null && !mood.getNote().isBlank())
                || (mood.getFrequency() != null && !mood.getFrequency().isBlank())
                || (mood.getRecentChange() != null && !mood.getRecentChange().isBlank())
                || (mood.getContext() != null && !mood.getContext().isBlank())
                || (mood.getLinkedMoodEntryId() != null && !mood.getLinkedMoodEntryId().isBlank());
    }

    private void validatePersonal(PersonalInfo personal, boolean full) {
        Integer age = personal.getAge();
        boolean ageOk = age != null && age >= MIN_AGE && age <= MAX_AGE;
        if (full) {
            if (!ageOk) {
                throw invalid("Age must be between " + MIN_AGE + " and " + MAX_AGE + ".");
            }
            if (isBlank(personal.getGender()) || personal.getGender().length() > 40) {
                throw invalid("Gender is required.");
            }
            if (isBlank(personal.getOccupation()) || personal.getOccupation().length() > 100) {
                throw invalid("Occupation is required.");
            }
        } else {
            if (age != null && !ageOk) {
                throw invalid("Age must be between " + MIN_AGE + " and " + MAX_AGE + ".");
            }
            if (personal.getGender() != null
                    && (isBlank(personal.getGender()) || personal.getGender().length() > 40)) {
                throw invalid("Gender is required.");
            }
            if (personal.getOccupation() != null
                    && (isBlank(personal.getOccupation()) || personal.getOccupation().length() > 100)) {
                throw invalid("Occupation is required.");
            }
        }
    }

    private void validateLifestyle(Lifestyle lifestyle, boolean full) {
        if ((full || lifestyle.getSleepHours() != null) && !inRange(lifestyle.getSleepHours(), 0, 12)) {
            throw invalid("Sleep hours must be between 0 and 12.");
        }
        // Choice fields follow the same rule as the sliders: a provided value
        // must be in range even in drafts; only absent (null) is lenient.
        if ((full || lifestyle.getExerciseFrequency() != null)
                && !inRange(lifestyle.getExerciseFrequency(), 0, 3)) {
            throw invalid("Exercise frequency has an invalid value.");
        }
        if ((full || lifestyle.getWaterIntake() != null)
                && !inRange(lifestyle.getWaterIntake(), 0, 3)) {
            throw invalid("Water intake has an invalid value.");
        }        if ((full || lifestyle.getScreenTime() != null) && !inRange(lifestyle.getScreenTime(), 0, 16)) {
            throw invalid("Screen time must be between 0 and 16.");
        }
        if ((full || lifestyle.getWorkingHours() != null)
                && !inRange(lifestyle.getWorkingHours(), 0, 14)) {
            throw invalid("Working hours must be between 0 and 14.");
        }
    }

    /**
     * @param full when true the list must contain exactly the questionnaire's
     *             item count with every value answered.
     */
    private void validateAnswerList(String code, List<Integer> answers, boolean full) {
        Questionnaire questionnaire = Questionnaire.byCode(code);
        if (questionnaire == null) {
            throw invalid("Unknown questionnaire: " + code);
        }
        if (answers == null) {
            if (full) {
                throw invalid("Answers are missing for " + code);
            }
            return;
        }
        if (answers.size() > questionnaire.items()) {
            throw invalid("Questionnaire " + code + " has too many answers.");
        }
        if (full && answers.size() != questionnaire.items()) {
            throw invalid("Questionnaire " + code + " requires exactly "
                    + questionnaire.items() + " answers (got " + answers.size() + ").");
        }
        for (Integer value : answers) {
            if (value == null || value < questionnaire.min() || value > questionnaire.max()) {
                throw invalid("Questionnaire " + code + " answer out of allowed range "
                        + questionnaire.min() + "-" + questionnaire.max() + ".");
            }
        }
    }

    private boolean inRange(Double value, double min, double max) {
        return value != null && value >= min && value <= max;
    }

    private boolean inRange(Integer value, int min, int max) {
        return value != null && value >= min && value <= max;
    }

    private boolean inRange(int value, int min, int max) {
        return value >= min && value <= max;
    }

    private boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    private ApiException invalid(String message) {
        return new ApiException(ErrorCode.VALIDATION_FAILED, message);
    }
}