package com.mindease.backend.screening.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import com.mindease.backend.screening.domain.QuestionnaireCatalog;
import com.mindease.backend.screening.domain.QuestionnaireCatalog.QuestionnaireDef;
import com.mindease.backend.screening.domain.QuestionnaireCatalog.LifestyleQuestionDef;
import com.mindease.backend.screening.domain.QuestionnaireCatalog.ScaleOption;
import com.mindease.backend.screening.domain.QuestionnaireCatalogRepository;

/**
 * Seeds the questionnaire catalog into MongoDB on startup if no catalog exists
 * yet. Idempotent and cheap: it only runs while the collection is empty, so
 * updating the catalog in a future release is done by bumping the version and
 * merging documents rather than re-seeding.
 */
@Component
public class QuestionnaireCatalogSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(QuestionnaireCatalogSeeder.class);

    private final QuestionnaireCatalogRepository repository;

    public QuestionnaireCatalogSeeder(QuestionnaireCatalogRepository repository) {
        this.repository = repository;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (repository.count() > 0) {
            log.info("Questionnaire catalog already present, skipping seed.");
            return;
        }
        QuestionnaireCatalog catalog = new QuestionnaireCatalog();
        catalog.setVersion("1.0");
        catalog.setQuestionnaires(List.of(
                phq9(),
                gad7(),
                pss10(),
                who5()));
        catalog.setLifestyle(lifestyleQuestions());
        catalog.setGenderOptions(List.of(
                "Female", "Male", "Non-binary", "Prefer not to say"));
        catalog.setOccupationOptions(List.of(
                "Student",
                "Employed full-time",
                "Working part-time",
                "Self-employed",
                "Homemaker",
                "Retired",
                "Unemployed",
                "Prefer not to say"));
        catalog.setCreatedAt(Instant.now());
        catalog.setUpdatedAt(Instant.now());
        repository.save(catalog);
        log.info("Seeded questionnaire catalog v{} (4 questionnaires, {} lifestyle questions).",
                catalog.getVersion(), catalog.getLifestyle().size());
    }

    private static List<ScaleOption> scaleOptions(String... labels) {
        List<ScaleOption> options = new ArrayList<>();
        for (int i = 0; i < labels.length; i++) {
            options.add(new ScaleOption(i, labels[i]));
        }
        return options;
    }

    private static QuestionnaireDef questionnaire(String code, String title,
                                                  String instruction, List<ScaleOption> options,
                                                  String... items) {
        return new QuestionnaireDef(code, title, instruction, options, List.of(items));
    }

    private static QuestionnaireDef phq9() {
        return questionnaire("phq9", "PHQ-9 Assessment",
                "Over the last 2 weeks, how often have you been bothered by the following problems?",
                scaleOptions("Not at all", "Several days",
                        "More than half the days", "Nearly every day"),
                "Little interest or pleasure in doing things",
                "Feeling down, depressed, or hopeless",
                "Trouble falling or staying asleep, or sleeping too much",
                "Feeling tired or having little energy",
                "Poor appetite or overeating",
                "Feeling bad about yourself — or that you are a failure or have let yourself or your family down",
                "Trouble concentrating on things, such as reading the newspaper or watching television",
                "Moving or speaking so slowly that other people could have noticed — or the opposite, being so fidgety or restless that you have been moving around a lot more than usual",
                "Thoughts that you would be better off dead, or of hurting yourself in some way");
    }

    private static QuestionnaireDef gad7() {
        return questionnaire("gad7", "GAD-7 Assessment",
                "Over the last 2 weeks, how often have you been bothered by the following problems?",
                scaleOptions("Not at all", "Several days",
                        "More than half the days", "Nearly every day"),
                "Feeling nervous, anxious, or on edge",
                "Not being able to stop or control worrying",
                "Worrying too much about different things",
                "Trouble relaxing",
                "Being so restless that it is hard to sit still",
                "Becoming easily annoyed or irritable",
                "Feeling afraid, as if something awful might happen");
    }

    private static QuestionnaireDef pss10() {
        return questionnaire("pss10", "PSS-10 Assessment",
                "In the last month, how often have you felt or thought the following?",
                scaleOptions("Never", "Almost never", "Sometimes",
                        "Fairly often", "Very often"),
                "Been upset because of something that happened unexpectedly?",
                "Felt that you were unable to control the important things in your life?",
                "Felt nervous and stressed?",
                "Felt confident about your ability to handle your personal problems?",
                "Felt that things were going your way?",
                "Found that you could not cope with all the things that you had to do?",
                "Been able to control irritations in your life?",
                "Felt that you were on top of things?",
                "Been angered because of things that were outside of your control?",
                "Felt difficulties were piling up so high that you could not overcome them?");
    }

    private static QuestionnaireDef who5() {
        return questionnaire("who5", "WHO-5 Assessment",
                "Over the last 2 weeks, how much of the time have you felt the following?",
                scaleOptions("At no time", "Some of the time",
                        "Less than half of the time", "More than half of the time",
                        "Most of the time", "All of the time"),
                "I have felt cheerful and in good spirits",
                "I have felt calm and relaxed",
                "I have felt active and vigorous",
                "I woke up feeling fresh and rested",
                "My daily life has been filled with things that interest me");
    }

    private static List<LifestyleQuestionDef> lifestyleQuestions() {
        return List.of(
                slider("sleepHours", "Sleep", "How many hours of sleep do you get on an average night?",
                        "Slide to select the number of hours", 0, 12, 0.5, "h", null),
                choice("exercise", "Exercise", "How often do you exercise in a typical week?",
                        "Choose the option that fits best",
                        List.of(new ScaleOption(0, "Never"),
                                new ScaleOption(1, "1-2 times a week"),
                                new ScaleOption(2, "3-4 times a week"),
                                new ScaleOption(3, "5 or more times a week"))),
                choice("water", "Water intake", "How many glasses of water do you drink each day?",
                        "Choose the option that fits best",
                        List.of(new ScaleOption(0, "Less than 2 glasses"),
                                new ScaleOption(1, "2-4 glasses"),
                                new ScaleOption(2, "5-7 glasses"),
                                new ScaleOption(3, "8 or more glasses"))),
                slider("screenTime", "Screen time", "How many hours a day do you spend on screens?",
                        "Slide to select the number of hours", 0, 16, 0.5, "h", null),
                slider("workingHours", "Work hours", "How many hours a day do you work or study?",
                        "Slide to select the number of hours", 0, 14, 0.5, "h", null));
    }

    private static LifestyleQuestionDef slider(String field, String label, String title,
                                               String hint, double min, double max,
                                               double step, String unit, List<ScaleOption> choices) {
        LifestyleQuestionDef def = new LifestyleQuestionDef();
        def.setField(field);
        def.setLabel(label);
        def.setTitle(title);
        def.setHint(hint);
        def.setType("slider");
        def.setMin(min);
        def.setMax(max);
        def.setStep(step);
        def.setUnit(unit);
        def.setChoices(choices == null ? new ArrayList<>() : choices);
        return def;
    }

    private static LifestyleQuestionDef choice(String field, String label, String title,
                                               String hint, List<ScaleOption> choices) {
        LifestyleQuestionDef def = new LifestyleQuestionDef();
        def.setField(field);
        def.setLabel(label);
        def.setTitle(title);
        def.setHint(hint);
        def.setType("choice");
        def.setMin(0);
        def.setMax(3);
        def.setStep(1);
        def.setUnit("");
        def.setChoices(choices);
        return def;
    }
}
