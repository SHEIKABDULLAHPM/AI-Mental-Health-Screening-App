package com.mindease.backend.features.physical.application;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.stereotype.Service;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.features.challenges.application.ChallengePeriodCalculator;
import com.mindease.backend.features.physical.domain.HydrationEntry;
import com.mindease.backend.features.physical.domain.HydrationEntryRepository;
import com.mindease.backend.features.physical.domain.MeasurementType;
import com.mindease.backend.features.physical.domain.WellnessGoal;
import com.mindease.backend.features.physical.domain.WellnessGoalRepository;
import com.mindease.backend.features.physical.dto.HydrationDtos;
import com.mindease.backend.security.UserTimeZoneHolder;

/**
 * Hydration logging and daily/weekly roll-ups.
 *
 * <p>Totals are always recomputed from the surviving entries, so editing or
 * deleting an entry immediately and exactly corrects every total and trend.
 * Days without any entry are reported as {@code null} consumption, never as a
 * zero.</p>
 */
@Service
public class HydrationService {

    static final int DEFAULT_HISTORY_DAYS = 14;
    static final int MAX_HISTORY_DAYS = 90;
    static final int DEFAULT_TARGET_ML = 2_000;

    private final HydrationEntryRepository entries;
    private final WellnessGoalRepository goals;
    private final LifestyleUnits units;

    public HydrationService(HydrationEntryRepository entries,
                            WellnessGoalRepository goals,
                            LifestyleUnits units) {
        this.entries = entries;
        this.goals = goals;
        this.units = units;
    }

    public HydrationDtos.HydrationResponse overview(String userId, Integer daysParam) {
        ZoneId zone = zone();
        LocalDate today = LocalDate.now(zone);
        int days = clampDays(daysParam);
        LocalDate from = today.minusDays(days - 1L);

        int target = targetMl(userId);
        boolean customized = goals.findByUserId(userId)
                .map(goal -> goal.getDailyHydrationMl() != null)
                .orElse(false);

        List<HydrationEntry> rows = entries
                .findByUserIdAndDateBetweenOrderByDateDesc(userId, from, today);

        Map<LocalDate, List<HydrationEntry>> byDay = new LinkedHashMap<>();
        for (HydrationEntry row : rows) {
            byDay.computeIfAbsent(row.getDate(), key -> new ArrayList<>()).add(row);
        }
        List<HydrationDtos.DayResponse> dayResponses = new ArrayList<>();
        for (Map.Entry<LocalDate, List<HydrationEntry>> entry : byDay.entrySet()) {
            List<HydrationEntry> dayEntries = entry.getValue();
            dayEntries.sort((a, b) -> a.getTimestamp().compareTo(b.getTimestamp()));
            double total = dayEntries.stream().mapToDouble(HydrationEntry::getAmountMl).sum();
            dayResponses.add(new HydrationDtos.DayResponse(
                    entry.getKey(), round(total), dayEntries.size(), mapEntries(dayEntries)));
        }

        HydrationDtos.DayResponse todayResponse = dayResponses.stream()
                .filter(day -> day.date().equals(today))
                .findFirst()
                .orElse(new HydrationDtos.DayResponse(today, 0d, 0, List.of()));

        return new HydrationDtos.HydrationResponse(
                "ml",
                target,
                customized,
                todayResponse,
                dayResponses,
                "Hydration needs vary with body size, activity, climate and health conditions. "
                        + "Your target is a personal starting point — adjust it with a clinician "
                        + "if you have a condition that affects fluid balance.");
    }

    public HydrationDtos.EntryResponse add(String userId, HydrationDtos.HydrationRequest request) {
        double ml = units.hydrationToMl(request.amount(), request.unit());
        Instant timestamp = request.timestamp() == null ? Instant.now() : request.timestamp();
        if (timestamp.isAfter(Instant.now().plusSeconds(300))) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Timestamp cannot be in the future");
        }
        LocalDate date = timestamp.atZone(zone()).toLocalDate();
        double existing = entries.findByUserIdAndDateOrderByTimestampAsc(userId, date).stream()
                .mapToDouble(HydrationEntry::getAmountMl).sum();
        if (existing + ml > LifestyleUnits.MAX_DAILY_HYDRATION_ML) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Daily hydration total would exceed the supported maximum of 15000 ml");
        }

        Instant now = Instant.now();
        HydrationEntry entry = new HydrationEntry();
        entry.setUserId(userId);
        entry.setDate(date);
        entry.setAmountMl(ml);
        entry.setTimestamp(timestamp);
        entry.setSource(MeasurementType.USER_ENTERED);
        entry.setCreatedAt(now);
        entry.setUpdatedAt(now);
        return map(entries.save(entry));
    }

    public HydrationDtos.EntryResponse update(String userId, String entryId,
                                              HydrationDtos.HydrationRequest request) {
        HydrationEntry entry = entries.findByIdAndUserId(entryId, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND, "Hydration entry not found"));
        double ml = units.hydrationToMl(request.amount(), request.unit());
        Instant timestamp = request.timestamp() == null ? entry.getTimestamp() : request.timestamp();
        if (timestamp.isAfter(Instant.now().plusSeconds(300))) {
            throw new ApiException(ErrorCode.BAD_REQUEST, "Timestamp cannot be in the future");
        }
        LocalDate date = timestamp.atZone(zone()).toLocalDate();
        double others = entries.findByUserIdAndDateOrderByTimestampAsc(userId, date).stream()
                .filter(existing -> !existing.getId().equals(entryId))
                .mapToDouble(HydrationEntry::getAmountMl).sum();
        if (others + ml > LifestyleUnits.MAX_DAILY_HYDRATION_ML) {
            throw new ApiException(ErrorCode.BAD_REQUEST,
                    "Daily hydration total would exceed the supported maximum of 15000 ml");
        }
        entry.setAmountMl(ml);
        entry.setTimestamp(timestamp);
        entry.setDate(date);
        entry.setUpdatedAt(Instant.now());
        return map(entries.save(entry));
    }

    public void delete(String userId, String entryId) {
        HydrationEntry entry = entries.findByIdAndUserId(entryId, userId)
                .orElseThrow(() -> new ApiException(ErrorCode.NOT_FOUND, "Hydration entry not found"));
        entries.delete(entry);
    }

    public HydrationDtos.HydrationResponse updateTarget(String userId, Integer targetMl) {
        WellnessGoal goal = goals.findByUserId(userId).orElseGet(() -> {
            WellnessGoal created = new WellnessGoal();
            created.setUserId(userId);
            created.setCreatedAt(Instant.now());
            return created;
        });
        goal.setDailyHydrationMl(targetMl);
        goal.setUpdatedAt(Instant.now());
        goals.save(goal);
        return overview(userId, null);
    }

    /** Today's total, or {@code null} when nothing was logged today. */
    public Double todayTotalMl(String userId, LocalDate date) {
        List<HydrationEntry> rows = entries.findByUserIdAndDateOrderByTimestampAsc(userId, date);
        if (rows.isEmpty()) {
            return null;
        }
        return round(rows.stream().mapToDouble(HydrationEntry::getAmountMl).sum());
    }

    public Integer targetMl(String userId) {
        return goals.findByUserId(userId)
                .map(goal -> goal.getDailyHydrationMl() == null
                        ? DEFAULT_TARGET_ML : goal.getDailyHydrationMl())
                .orElse(DEFAULT_TARGET_ML);
    }

    private List<HydrationDtos.EntryResponse> mapEntries(List<HydrationEntry> rows) {
        List<HydrationDtos.EntryResponse> mapped = new ArrayList<>();
        for (HydrationEntry row : rows) {
            mapped.add(map(row));
        }
        return mapped;
    }

    private HydrationDtos.EntryResponse map(HydrationEntry entry) {
        return new HydrationDtos.EntryResponse(
                entry.getId(),
                entry.getDate(),
                round(entry.getAmountMl()),
                entry.getTimestamp(),
                entry.getSource() == null ? "USER_ENTERED" : entry.getSource().name());
    }

    private static int clampDays(Integer daysParam) {
        int days = daysParam == null ? DEFAULT_HISTORY_DAYS : daysParam;
        return Math.min(Math.max(days, 1), MAX_HISTORY_DAYS);
    }

    private static ZoneId zone() {
        return ChallengePeriodCalculator.zone(UserTimeZoneHolder.get());
    }

    private static double round(double value) {
        return Math.round(value * 10d) / 10d;
    }
}
