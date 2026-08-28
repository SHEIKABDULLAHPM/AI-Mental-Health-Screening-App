package com.mindease.backend.screening.domain;

/** Personal background captured by the screening UI. */
public class PersonalInfo {

    private Integer age;

    private String gender;

    private String occupation;

    public PersonalInfo() {
    }

    public Integer getAge() {
        return age;
    }

    public void setAge(Integer age) {
        this.age = age;
    }

    public String getGender() {
        return gender;
    }

    public void setGender(String gender) {
        this.gender = gender;
    }

    public String getOccupation() {
        return occupation;
    }

    public void setOccupation(String occupation) {
        this.occupation = occupation;
    }
}