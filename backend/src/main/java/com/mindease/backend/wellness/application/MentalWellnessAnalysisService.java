package com.mindease.backend.wellness.application;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.mood.domain.MoodEntry;
import com.mindease.backend.features.mood.domain.MoodEntryRepository;
import com.mindease.backend.features.physical.application.WellnessGoalService;
import com.mindease.backend.features.physical.dto.WellnessGoalDtos;
import com.mindease.backend.screening.domain.Screening;
import com.mindease.backend.screening.domain.ScreeningRepository;
import com.mindease.backend.screening.domain.ScreeningStatus;
import com.mindease.backend.wellness.domain.WellnessAnalysisRecord;
import com.mindease.backend.wellness.domain.WellnessProfile;
import com.mindease.backend.wellness.domain.WellnessProfileRepository;
import com.mindease.backend.wellness.dto.MentalWellnessAnalysisDto;
import com.mindease.backend.wellness.dto.WellnessMetricDto;

@Service
public class MentalWellnessAnalysisService {

    private static final Logger log = LoggerFactory.getLogger(MentalWellnessAnalysisService.class);
    private static final String SCHEMA_VERSION = "1.0";
    private static final String SOURCE = "wellness-mental-analysis";

    private final WellnessProfileRepository profiles;
    private final ScreeningRepository screenings;
    private final MoodEntryRepository moodEntries;
    private final WellnessAnalysisPipeline pipeline;
    private final WellnessGoalService wellnessGoalService;

    @org.springframework.beans.factory.annotation.Autowired
    public MentalWellnessAnalysisService(WellnessProfileRepository profiles,
                                         ScreeningRepository screenings,
                                         MoodEntryRepository moodEntries,
                                         WellnessAnalysisPipeline pipeline,
                                         WellnessGoalService wellnessGoalService) {
        this.profiles = profiles;
        this.screenings = screenings;
        this.moodEntries = moodEntries;
        this.pipeline = pipeline;
        this.wellnessGoalService = wellnessGoalService;
    }

    public MentalWellnessAnalysisService(WellnessProfileRepository profiles,
                                         ScreeningRepository screenings,
                                         MoodEntryRepository moodEntries,
                                         WellnessAnalysisPipeline pipeline) {
        this(profiles, screenings, moodEntries, pipeline, null);
    }

    public MentalWellnessAnalysisDto analyze(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new ApiException(ErrorCode.UNAUTHORIZED, "Authentication required");
        }

        Optional<WellnessProfile> profileOpt = profiles.findFirstByUserIdOrderByCreatedAtDesc(userId);
        List<Screening> userScreenings = screenings.findByUserIdOrderByUpdatedAtDesc(userId);
        Screening latestCompleted = userScreenings.stream()
                .filter(s -> s.getStatus() == ScreeningStatus.COMPLETED)
                .findFirst()
                .orElse(null);

        List<MoodEntry> recentMoods = moodEntries.findByUserIdOrderByRecordedAtDesc(userId,
                org.springframework.data.domain.PageRequest.of(0, 30));
        Instant latestMoodAt = recentMoods.stream().map(MoodEntry::getRecordedAt)
                .filter(java.util.Objects::nonNull)
                .max(java.util.Comparator.naturalOrder())
                .orElse(null);

        if (profileOpt.isEmpty() && latestCompleted == null) {
            return MentalWellnessAnalysisDto.unavailable(
                    "Complete a screening to generate a mental wellness analysis.");
        }

        WellnessProfile profile = profileOpt.orElse(null);
        boolean hasProfile = profile != null;
        boolean hasAssessment = latestCompleted != null;
        boolean hasMoodData = !recentMoods.isEmpty();

        Integer wellnessScore = profile != null ? profile.getWellnessScore() : null;
        String stressLevel = profile != null ? profile.getStressLevel() : null;
        Integer lifestyleScore = profile != null ? profile.getLifestyleScore() : null;
        String sleepQuality = profile != null ? profile.getSleepQuality() : null;
        String primaryFocus = profile != null ? profile.getPrimaryFocus() : null;
        String insight = profile != null ? profile.getAiInsight() : null;
        boolean safetyFlag = Boolean.TRUE.equals(profile != null ? profile.getSafetyFlag() : Boolean.FALSE);

        List<String> recommendations = buildRecommendations(wellnessScore, stressLevel, sleepQuality, safetyFlag);
        if (insight == null || insight.isBlank()) {
            insight = buildDeterministicInsight(wellnessScore, stressLevel, primaryFocus, sleepQuality);
        }

        List<String> inputRefs = new ArrayList<>();
        if (hasProfile && profile.getId() != null) {
            inputRefs.add("wellness_profile:" + profile.getId());
        }
        if (hasAssessment && latestCompleted.getId() != null) {
            inputRefs.add("screening:" + latestCompleted.getId());
        }
        if (hasMoodData && !recentMoods.isEmpty() && recentMoods.get(0).getId() != null) {
            inputRefs.add("mood_entries:" + recentMoods.size());
        }

        MentalWellnessAnalysisDto.InputSummary inputSummary = new MentalWellnessAnalysisDto.InputSummary(
                hasProfile,
                hasAssessment,
                hasMoodData,
                userScreenings.size(),
                latestCompleted != null ? latestCompleted.getUpdatedAt() : null,
                latestMoodAt);

        MentalWellnessAnalysisDto.Provenance provenance = new MentalWellnessAnalysisDto.Provenance(
                SOURCE,
                SCHEMA_VERSION,
                inputRefs,
                Instant.now());

        // Metrics are the same aggregates shown on screen, so the history
        // comparison can be explained to the user without new data access.
        List<WellnessMetricDto> metrics = new ArrayList<>();
        if (wellnessScore != null) {
            metrics.add(new WellnessMetricDto("wellness_score", "Wellness score", wellnessScore, "/100"));
        }
        if (lifestyleScore != null) {
            metrics.add(new WellnessMetricDto("lifestyle_score", "Lifestyle score", lifestyleScore, "/100"));
        }
        Double stressScore = stressScore(stressLevel);
        if (stressScore != null) {
            metrics.add(new WellnessMetricDto("stress_level", "Stress level", stressScore, "/100"));
        }
        metrics.add(new WellnessMetricDto("mood_checkins", "Mood check-ins", recentMoods.size(), "entries"));
        if (latestCompleted != null && latestCompleted.getUpdatedAt() != null) {
            long days = java.time.Duration.between(latestCompleted.getUpdatedAt(), Instant.now()).toDays();
            metrics.add(new WellnessMetricDto("days_since_assessment", "Days since last screening",
                    Math.max(0, days), "days"));
        }

        List<String> patterns = new ArrayList<>();
        if (wellnessScore != null) {
            patterns.add("Wellness score is " + wellnessScore + " out of 100.");
        }
        if (stressLevel != null) {
            patterns.add("Reported stress level is " + stressLevel + ".");
        }
        if (sleepQuality != null) {
            patterns.add("Reported sleep quality is " + sleepQuality + ".");
        }
        if (hasMoodData) {
            patterns.add(recentMoods.size() + " mood check-ins recorded recently.");
        }

        WellnessAnalysisPipeline.Outcome outcome = pipeline.run(
                userId,
                WellnessAnalysisRecord.TYPE_MENTAL,
                metrics,
                patterns,
                insight,
                recommendations,
                wellnessScore,
                null,
                inputRefs);

        List<MentalWellnessAnalysisDto.GoalTargetSuggestion> goalSuggestions =
                buildGoalSuggestions(sleepQuality, stressLevel);

        if (wellnessGoalService != null && !goalSuggestions.isEmpty()) {
            try {
                List<WellnessGoalDtos.AiRecommendation> aiRecs = goalSuggestions.stream()
                        .map(g -> new WellnessGoalDtos.AiRecommendation(g.metric(), g.value(), g.rationale()))
                        .toList();
                wellnessGoalService.applyAiRecommendations(userId, aiRecs);
            } catch (Exception e) {
                log.warn("Could not apply mental goal suggestions: {}", e.getMessage());
            }
        }

        return new MentalWellnessAnalysisDto(
                UUID.randomUUID().toString(),
                "MENTAL",
                Instant.now(),
                true,
                wellnessScore,
                stressLevel,
                lifestyleScore,
                sleepQuality,
                primaryFocus,
                outcome.narrative(),
                outcome.recommendations(),
                outcome.generatedBy(),
                safetyFlag,
                false,
                null,
                inputSummary,
                provenance,
                outcome.advice(),
                outcome.focusAreas(),
                outcome.nextActions(),
                outcome.comparison(),
                goalSuggestions);
    }

    /**
     * Self-reported sleep quality and stress levels are the mental signals used
     * to suggest supportive sleep and active relaxation targets.
     */
    private static List<MentalWellnessAnalysisDto.GoalTargetSuggestion> buildGoalSuggestions(
            String sleepQuality, String stressLevel) {
        List<MentalWellnessAnalysisDto.GoalTargetSuggestion> suggestions = new ArrayList<>();
        if (sleepQuality != null) {
            String q = sleepQuality.toLowerCase(java.util.Locale.ROOT);
            if (q.contains("poor") || q.contains("bad") || q.contains("fair")) {
                suggestions.add(new MentalWellnessAnalysisDto.GoalTargetSuggestion(
                        "dailySleepMinutes", 480, "min",
                        "You reported " + sleepQuality.toLowerCase(java.util.Locale.ROOT)
                                + " sleep quality; a consistent 8-hour target may help."));
            }
        }
        if (stressLevel != null) {
            String s = stressLevel.toUpperCase(java.util.Locale.ROOT);
            if ("HIGH".equals(s) || "MODERATE".equals(s) || "SEVERE".equals(s)) {
                suggestions.add(new MentalWellnessAnalysisDto.GoalTargetSuggestion(
                        "dailyActiveMinutes", 30, "min",
                        "Aim for 30 minutes of daily calming movement or relaxation exercise to reduce stress."));
            }
        }
        return suggestions;
    }

    /** Maps the stored stress band onto the comparison scale. */
    private static Double stressScore(String stressLevel) {
        if (stressLevel == null) {
            return null;
        }
        return switch (stressLevel.toUpperCase(java.util.Locale.ROOT)) {
            case "LOW" -> 25.0;
            case "MODERATE", "MEDIUM" -> 55.0;
            case "HIGH", "SEVERE" -> 85.0;
            default -> null;
        };
    }

    private String buildDeterministicInsight(Integer wellnessScore, String stressLevel,
                                             String primaryFocus, String sleepQuality) {
        StringBuilder sb = new StringBuilder();
        if (wellnessScore != null) {
            sb.append("Your current wellness score is ").append(wellnessScore).append(" out of 100. ");
        }
        if (stressLevel != null) {
            sb.append("Stress level appears ").append(stressLevel.toLowerCase()).append(". ");
        }
        if (primaryFocus != null) {
            sb.append("Primary focus: ").append(primaryFocus.replace('_', ' ').toLowerCase()).append(". ");
        }
        if (sleepQuality != null) {
            sb.append("Reported sleep quality is ").append(sleepQuality.toLowerCase()).append(". ");
        }
        sb.append("Continue tracking your mood and habits to build a more complete picture over time.");
        return sb.toString();
    }

    private List<String> buildRecommendations(Integer wellnessScore, String stressLevel,
                                              String sleepQuality, boolean safetyFlag) {
        List<String> recs = new ArrayList<>();
        if (safetyFlag) {
            recs.add("Use your Safety Support resources if you need immediate help.");
        }
        if (stressLevel != null && ("HIGH".equals(stressLevel) || "MODERATE".equals(stressLevel))) {
            recs.add("Try a short breathing exercise or guided relaxation to regulate stress.");
        }
        if (sleepQuality != null && "POOR".equals(sleepQuality)) {
            recs.add("Focus on a consistent wind-down routine to improve sleep quality.");
        }
        if (wellnessScore == null || wellnessScore < 60) {
            recs.add("Engage in small daily activities like a short walk or mood check-in.");
        }
        if (recs.isEmpty()) {
            recs.add("Keep up your positive habits and continue regular mood tracking.");
        }
        return recs;
    }
}
