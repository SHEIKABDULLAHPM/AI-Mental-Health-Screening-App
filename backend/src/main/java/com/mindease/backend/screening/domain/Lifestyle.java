package com.mindease.backend.screening.domain;

/**
 * Lifestyle inputs. Slider fields are stored as doubles (half-hour steps),
 * choice fields as integers (0-3).
 */
public class Lifestyle {

    private Double sleepHours;
    private Integer exerciseFrequency;
    private Integer waterIntake;
    private Double screenTime;
    private Double workingHours;

    public Lifestyle() {
    }

    public Double getSleepHours() {
        return sleepHours;
    }

    public void setSleepHours(Double sleepHours) {
        this.sleepHours = sleepHours;
    }

    public Integer getExerciseFrequency() {
        return exerciseFrequency;
    }

    public void setExerciseFrequency(Integer exerciseFrequency) {
        this.exerciseFrequency = exerciseFrequency;
    }

    public Integer getWaterIntake() {
        return waterIntake;
    }

    public void setWaterIntake(Integer waterIntake) {
        this.waterIntake = waterIntake;
    }

    public Double getScreenTime() {
        return screenTime;
    }

    public void setScreenTime(Double screenTime) {
        this.screenTime = screenTime;
    }

    public Double getWorkingHours() {
        return workingHours;
    }

    public void setWorkingHours(Double workingHours) {
        this.workingHours = workingHours;
    }
}