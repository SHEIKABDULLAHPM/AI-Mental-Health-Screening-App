package com.mindease.backend.wellness.application;

import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Service;

import com.mindease.backend.screening.domain.Lifestyle;
import com.mindease.backend.screening.domain.Screening;

/**
 * Deterministic wellbeing scoring computed server-side from a completed
 * assessment. This is the single source of truth for the wellness score and
 * insight text — the client no longer computes anything itself.
 *
 * <p>Scoring follows the validated PHQ-9 / GAD-7 / PSS-10 / WHO-5 conventions:
 * reverse-scored PSS items (4, 5, 7, 8) are inverted, sub-scores are normalized
 * to 0-100 and the composite is a weighted blend.</p>
 */
@Service
public class WellnessAnalysisService {

    public record Analysis(
            int wellnessScore,
            String stressLevel,
            int lifestyleScore,
            String sleepQuality,
            String primaryFocus,
            String aiInsight) {
    }

    /**
     * Deterministic sub-scores used as the minimal, anonymized AI job input.
     */
    public record Scores(
            int phq9,
            int gad7,
            int pss10,
            int who5,
            int whoPercent) {
    }

    public Scores scores(Screening screening) {
        int phqTotal = sum(screening.getAssessments(), "phq9");
        int gadTotal = sum(screening.getAssessments(), "gad7");
        int pssTotal = pssScore(screening.getAssessments());
        int whoRaw = sum(screening.getAssessments(), "who5");
        return new Scores(phqTotal, gadTotal, pssTotal, whoRaw, clamp(whoRaw * 4, 0, 100));
    }

    public Analysis analyze(Screening screening) {
        Scores s = scores(screening);
        int phqTotal = s.phq9();
        int gadTotal = s.gad7();
        int pssTotal = s.pss10();
        int whoPercent = s.whoPercent();

        double phqScore = 100.0 * (27 - phqTotal) / 27;
        double gadScore = 100.0 * (21 - gadTotal) / 21;
        double pssScore = 100.0 - (pssTotal / 40.0 * 100);
        int wellnessScore = clamp(
                (int) Math.round(0.3 * phqScore + 0.25 * gadScore + 0.2 * pssScore + 0.25 * whoPercent),
                0, 100);

        String stress = stressLevel(gadTotal, pssTotal);
        String sleep = sleepQuality(screening.getLifestyle());
        int lifestyleScore = lifestyleScore(screening.getLifestyle());
        String focus = focus(stress, sleep, phqTotal, whoPercent);

        return new Analysis(
                wellnessScore,
                stress,
                lifestyleScore,
                sleep,
                focus,
                insight(focus, phqTotal, gadTotal, pssTotal, whoPercent, sleep));
    }

    private int sum(Map<String, List<Integer>> assessments, String code) {
        List<Integer> values = assessments.get(code);
        if (values == null) {
            return 0;
        }
        int total = 0;
        for (int v : values) {
            if (v >= 0) {
                total += v;
            }
        }
        return total;
    }

    private int pssScore(Map<String, List<Integer>> assessments) {
        List<Integer> values = assessments.get("pss10");
        if (values == null) {
            return 0;
        }
        int total = 0;
        for (int i = 0; i < values.size(); i++) {
            int v = values.get(i);
            if (v < 0) {
                continue;
            }
            total += (i == 3 || i == 4 || i == 6 || i == 7) ? 4 - v : v;
        }
        return total;
    }

    private String stressLevel(int gadTotal, int pssTotal) {
        int gadLvl = gadTotal <= 4 ? 0 : gadTotal <= 9 ? 1 : gadTotal <= 14 ? 2 : 3;
        int pssLvl = pssTotal <= 13 ? 0 : pssTotal <= 26 ? 1 : 2;
        int maxLvl = Math.max(gadLvl, pssLvl);
        if (maxLvl <= 1) {
            return "LOW";
        }
        return maxLvl == 2 ? "MODERATE" : "HIGH";
    }

    private String sleepQuality(Lifestyle lifestyle) {
        Double hours = lifestyle.getSleepHours();
        if (hours == null) {
            return "FAIR";
        }
        if (hours >= 7 && hours <= 9) {
            return "GOOD";
        }
        return hours >= 5 ? "FAIR" : "POOR";
    }

    private int lifestyleScore(Lifestyle lifestyle) {
        double points = 0;
        int count = 0;

        if (lifestyle.getSleepHours() != null) {
            count++;
            double h = lifestyle.getSleepHours();
            points += (h >= 7 && h <= 9) ? 100
                    : (h >= 6 || h == 10) ? 70
                            : (h >= 5 || h == 11) ? 45
                                    : 20;
        }
        if (lifestyle.getExerciseFrequency() != null) {
            count++;
            int[] table = {20, 50, 80, 100};
            int idx = Math.max(0, Math.min(3, lifestyle.getExerciseFrequency()));
            points += table[idx];
        }
        if (lifestyle.getWaterIntake() != null) {
            count++;
            int[] table = {25, 50, 75, 100};
            int idx = Math.max(0, Math.min(3, lifestyle.getWaterIntake()));
            points += table[idx];
        }
        if (lifestyle.getScreenTime() != null) {
            count++;
            double s = lifestyle.getScreenTime();
            points += s < 3 ? 100 : s <= 6 ? 80 : s <= 9 ? 55 : 30;
        }
        if (lifestyle.getWorkingHours() != null) {
            count++;
            double w = lifestyle.getWorkingHours();
            points += w <= 8 ? 90 : w <= 10 ? 70 : w <= 12 ? 50 : 30;
        }

        return count == 0 ? 0 : clamp((int) Math.round(points / count), 0, 100);
    }

    private String focus(String stress, String sleep, int phqTotal, int whoPercent) {
        if ("HIGH".equals(stress)) {
            return "STRESS_MANAGEMENT";
        }
        if ("POOR".equals(sleep)) {
            return "SLEEP";
        }
        if (phqTotal >= 10) {
            return "MOOD_SUPPORT";
        }
        if (whoPercent < 50) {
            return "WELLBEING";
        }
        return "BALANCE";
    }

    private String insight(String focus, int phq, int gad, int pss, int who, String sleep) {
        StringBuilder sb = new StringBuilder();
        sb.append("Your responses suggest ").append(summaryLine(phq, gad, pss, who)).append(".");
        switch (focus) {
            case "STRESS_MANAGEMENT" -> sb.append(" Your primary focus for the coming week is stress management.")
                    .append(" Try the 4-7-8 breathing technique and short mindful walks whenever you feel overwhelmed.");
            case "SLEEP" -> sb.append(" Improving your sleep is the highest-impact step you can take right now.")
                    .append(" Aim for 7-9 hours of rest and keep a consistent bedtime schedule.");
            case "MOOD_SUPPORT" -> sb.append(" Your primary focus is mood support.")
                    .append(" Small daily wins, gentle movement, and talking to someone you trust can help lift your mood.");
            case "WELLBEING" -> sb.append(" Your primary focus is boosting your everyday wellbeing.")
                    .append(" Nurture activities that bring you joy and stay connected with people who matter to you.");
            default -> sb.append(" Your responses look well-balanced right now.")
                    .append(" Keep up your current routines — consistency is your strongest tool for staying well.");
        }
        sb.append(" This insight is guidance, not a diagnosis. A mental health professional can provide a complete evaluation.");
        return sb.toString();
    }

    private String summaryLine(int phq, int gad, int pss, int who) {
        StringBuilder flags = new StringBuilder();
        int count = 0;
        if (phq >= 10) {
            appendFlag(flags, count++ > 0, "some signs of low mood");
        } else if (phq >= 5) {
            appendFlag(flags, count++ > 0, "a mild dip in mood");
        }
        if (gad >= 10) {
            appendFlag(flags, count++ > 0, "noticeable anxiety");
        } else if (gad >= 5) {
            appendFlag(flags, count++ > 0, "some anxious feelings");
        }
        if (pss >= 27) {
            appendFlag(flags, count++ > 0, "elevated stress levels");
        } else if (pss >= 14) {
            appendFlag(flags, count++ > 0, "moderate stress");
        }
        if (who < 50) {
            appendFlag(flags, count++ > 0, "lower everyday energy");
        }
        if (count == 0) {
            return "a generally balanced state of wellbeing";
        }
        if (count == 1) {
            return flags.toString();
        }
        return joinFlags(flags, count);
    }

    private void appendFlag(StringBuilder sb, boolean and, String text) {
        if (sb.length() > 0) {
            sb.append(and ? ", " : " ");
        }
        sb.append(text);
    }

    private String joinFlags(StringBuilder flags, int count) {
        String joined = flags.toString();
        int lastComma = joined.lastIndexOf(", ");
        if (lastComma < 0) {
            return joined;
        }
        return joined.substring(0, lastComma) + " and " + joined.substring(lastComma + 2);
    }

    private int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}
