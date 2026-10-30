package com.mindease.backend.features.physical.application;

import org.springframework.stereotype.Component;

/**
 * Unit normalization for user-entered lifestyle data.
 *
 * <p>Deliberately separate from {@link HealthDataValidator}: device readings are
 * validated per metric enum, while lifestyle entries arrive with human units
 * (litres, fluid ounces, pounds, inches) that only this layer knows how to
 * convert. Unknown units are rejected rather than guessed.</p>
 */
@Component
public class LifestyleUnits {

    public static final double MAX_HYDRATION_ENTRY_ML = 5_000d;
    public static final double MAX_DAILY_HYDRATION_ML = 15_000d;
    public static final double MIN_WEIGHT_KG = 2d;
    public static final double MAX_WEIGHT_KG = 500d;
    public static final double MIN_HEIGHT_CM = 30d;
    public static final double MAX_HEIGHT_CM = 300d;

    /** Converts a hydration amount to millilitres. Default unit: ml. */
    public double hydrationToMl(Double amount, String unit) {
        if (amount == null || amount.isNaN() || amount.isInfinite()) {
            throw new IllegalArgumentException("Amount must be a finite number");
        }
        String normalized = normalizeUnit(unit, "ml");
        double ml = switch (normalized) {
            case "ml", "millilitre", "milliliter", "millilitres", "milliliters" -> amount;
            case "l", "litre", "liter", "litres", "liters" -> amount * 1000d;
            case "floz", "fl_oz", "fl-oz", "fluid_ounce", "fluid_ounces", "oz" -> amount * 29.5735d;
            case "cup", "cups" -> amount * 240d;
            default -> throw new IllegalArgumentException("Unsupported hydration unit: " + unit);
        };
        if (ml <= 0) {
            throw new IllegalArgumentException("Amount must be greater than zero");
        }
        if (ml > MAX_HYDRATION_ENTRY_ML) {
            throw new IllegalArgumentException("A single entry cannot exceed 5000 ml");
        }
        return round(ml, 1);
    }

    /** Converts a body weight to kilograms. Default unit: kg. */
    public double weightToKg(Double weight, String unit) {
        if (weight == null || weight.isNaN() || weight.isInfinite()) {
            throw new IllegalArgumentException("Weight must be a finite number");
        }
        String normalized = normalizeUnit(unit, "kg");
        double kg = switch (normalized) {
            case "kg", "kilogram", "kilograms" -> weight;
            case "lb", "lbs", "pound", "pounds" -> weight * 0.45359237d;
            case "st", "stone", "stones" -> weight * 6.35029318d;
            default -> throw new IllegalArgumentException("Unsupported weight unit: " + unit);
        };
        if (kg < MIN_WEIGHT_KG || kg > MAX_WEIGHT_KG) {
            throw new IllegalArgumentException("Weight must be between 2 and 500 kg");
        }
        return round(kg, 2);
    }

    /** Converts a body height to centimetres. Default unit: cm. */
    public double heightToCm(Double height, String unit) {
        if (height == null || height.isNaN() || height.isInfinite()) {
            throw new IllegalArgumentException("Height must be a finite number");
        }
        String normalized = normalizeUnit(unit, "cm");
        double cm = switch (normalized) {
            case "cm", "centimetre", "centimeter", "centimetres", "centimeters" -> height;
            case "m", "metre", "meter", "metres", "meters" -> height * 100d;
            case "in", "inch", "inches" -> height * 2.54d;
            case "ft", "foot", "feet" -> height * 30.48d;
            default -> throw new IllegalArgumentException("Unsupported height unit: " + unit);
        };
        if (cm < MIN_HEIGHT_CM || cm > MAX_HEIGHT_CM) {
            throw new IllegalArgumentException("Height must be between 30 and 300 cm");
        }
        return round(cm, 1);
    }

    /** Human-readable category for a BMI value; never a diagnosis. */
    public String bmiCategory(double bmi) {
        if (bmi < 18.5) {
            return "BELOW_REFERENCE_RANGE";
        }
        if (bmi < 25) {
            return "REFERENCE_RANGE";
        }
        if (bmi < 30) {
            return "ABOVE_REFERENCE_RANGE";
        }
        return "WELL_ABOVE_REFERENCE_RANGE";
    }

    public String bmiLabel(String category) {
        return switch (category) {
            case "BELOW_REFERENCE_RANGE" -> "Below the WHO reference range";
            case "REFERENCE_RANGE" -> "Within the WHO reference range";
            case "ABOVE_REFERENCE_RANGE" -> "Above the WHO reference range";
            default -> "Well above the WHO reference range";
        };
    }

    private static String normalizeUnit(String unit, String fallback) {
        if (unit == null || unit.isBlank()) {
            return fallback;
        }
        return unit.trim().toLowerCase().replace(" ", "_");
    }

    private static double round(double value, int decimals) {
        double factor = Math.pow(10, decimals);
        return Math.round(value * factor) / factor;
    }
}
