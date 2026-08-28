package com.mindease.backend.screening.domain;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Server-side catalog of every question the screening flow renders: the four
 * clinical questionnaires (PHQ-9, GAD-7, PSS-10, WHO-5), the lifestyle
 * questions and the personal-info picker options. Seeded once on startup and
 * served to the client through {@code GET /screenings/questions} so the app no
 * longer hardcodes question content.
 */
@Document(collection = "questionnaire_catalog")
public class QuestionnaireCatalog {

    @Id
    private String id;

    private String version;

    private List<QuestionnaireDef> questionnaires = new ArrayList<>();

    private List<LifestyleQuestionDef> lifestyle = new ArrayList<>();

    private List<String> genderOptions = new ArrayList<>();

    private List<String> occupationOptions = new ArrayList<>();

    private Instant createdAt;

    private Instant updatedAt;

    public QuestionnaireCatalog() {
    }

    /** One clinical questionnaire: scale options + ordered question texts. */
    public static class QuestionnaireDef {
        private String code;
        private String title;
        private String instruction;
        private List<ScaleOption> options = new ArrayList<>();
        private List<String> items = new ArrayList<>();

        public QuestionnaireDef() {
        }

        public QuestionnaireDef(String code, String title, String instruction,
                                List<ScaleOption> options, List<String> items) {
            this.code = code;
            this.title = title;
            this.instruction = instruction;
            this.options = options;
            this.items = items;
        }

        public String getCode() {
            return code;
        }

        public void setCode(String code) {
            this.code = code;
        }

        public String getTitle() {
            return title;
        }

        public void setTitle(String title) {
            this.title = title;
        }

        public String getInstruction() {
            return instruction;
        }

        public void setInstruction(String instruction) {
            this.instruction = instruction;
        }

        public List<ScaleOption> getOptions() {
            return options;
        }

        public void setOptions(List<ScaleOption> options) {
            this.options = options;
        }

        public List<String> getItems() {
            return items;
        }

        public void setItems(List<String> items) {
            this.items = items;
        }
    }

    /** A single scale option (value 0..max with a human label). */
    public static class ScaleOption {
        private int value;
        private String label;

        public ScaleOption() {
        }

        public ScaleOption(int value, String label) {
            this.value = value;
            this.label = label;
        }

        public int getValue() {
            return value;
        }

        public void setValue(int value) {
            this.value = value;
        }

        public String getLabel() {
            return label;
        }

        public void setLabel(String label) {
            this.label = label;
        }
    }

    /** A lifestyle question: slider or choice picker. */
    public static class LifestyleQuestionDef {
        private String field;
        private String label;
        private String title;
        private String hint;
        private String type;
        private double min;
        private double max;
        private double step;
        private String unit;
        private List<ScaleOption> choices = new ArrayList<>();

        public LifestyleQuestionDef() {
        }

        public String getField() {
            return field;
        }

        public void setField(String field) {
            this.field = field;
        }

        public String getLabel() {
            return label;
        }

        public void setLabel(String label) {
            this.label = label;
        }

        public String getTitle() {
            return title;
        }

        public void setTitle(String title) {
            this.title = title;
        }

        public String getHint() {
            return hint;
        }

        public void setHint(String hint) {
            this.hint = hint;
        }

        public String getType() {
            return type;
        }

        public void setType(String type) {
            this.type = type;
        }

        public double getMin() {
            return min;
        }

        public void setMin(double min) {
            this.min = min;
        }

        public double getMax() {
            return max;
        }

        public void setMax(double max) {
            this.max = max;
        }

        public double getStep() {
            return step;
        }

        public void setStep(double step) {
            this.step = step;
        }

        public String getUnit() {
            return unit;
        }

        public void setUnit(String unit) {
            this.unit = unit;
        }

        public List<ScaleOption> getChoices() {
            return choices;
        }

        public void setChoices(List<ScaleOption> choices) {
            this.choices = choices;
        }
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getVersion() {
        return version;
    }

    public void setVersion(String version) {
        this.version = version;
    }

    public List<QuestionnaireDef> getQuestionnaires() {
        return questionnaires;
    }

    public void setQuestionnaires(List<QuestionnaireDef> questionnaires) {
        this.questionnaires = questionnaires;
    }

    public List<LifestyleQuestionDef> getLifestyle() {
        return lifestyle;
    }

    public void setLifestyle(List<LifestyleQuestionDef> lifestyle) {
        this.lifestyle = lifestyle;
    }

    public List<String> getGenderOptions() {
        return genderOptions;
    }

    public void setGenderOptions(List<String> genderOptions) {
        this.genderOptions = genderOptions;
    }

    public List<String> getOccupationOptions() {
        return occupationOptions;
    }

    public void setOccupationOptions(List<String> occupationOptions) {
        this.occupationOptions = occupationOptions;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }
}
