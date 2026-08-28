package com.mindease.backend.ai.domain;

/**
 * Deterministic wellness analysis snapshot attached to an AI job. This is the
 * minimal, already-anonymized input the AI service may use - raw assessment
 * answers are never sent to the LLM.
 */
public class DeterministicScores {

    private Integer phq9;
    private Integer gad7;
    private Integer pss10;
    private Integer who5;
    private Integer wellnessScore;
    private String stressLevel;
    private Integer lifestyleScore;
    private String sleepQuality;
    private String primaryFocus;

    public DeterministicScores() {
    }

    public Integer getPhq9() {
        return phq9;
    }

    public void setPhq9(Integer phq9) {
        this.phq9 = phq9;
    }

    public Integer getGad7() {
        return gad7;
    }

    public void setGad7(Integer gad7) {
        this.gad7 = gad7;
    }

    public Integer getPss10() {
        return pss10;
    }

    public void setPss10(Integer pss10) {
        this.pss10 = pss10;
    }

    public Integer getWho5() {
        return who5;
    }

    public void setWho5(Integer who5) {
        this.who5 = who5;
    }

    public Integer getWellnessScore() {
        return wellnessScore;
    }

    public void setWellnessScore(Integer wellnessScore) {
        this.wellnessScore = wellnessScore;
    }

    public String getStressLevel() {
        return stressLevel;
    }

    public void setStressLevel(String stressLevel) {
        this.stressLevel = stressLevel;
    }

    public Integer getLifestyleScore() {
        return lifestyleScore;
    }

    public void setLifestyleScore(Integer lifestyleScore) {
        this.lifestyleScore = lifestyleScore;
    }

    public String getSleepQuality() {
        return sleepQuality;
    }

    public void setSleepQuality(String sleepQuality) {
        this.sleepQuality = sleepQuality;
    }

    public String getPrimaryFocus() {
        return primaryFocus;
    }

    public void setPrimaryFocus(String primaryFocus) {
        this.primaryFocus = primaryFocus;
    }
}
