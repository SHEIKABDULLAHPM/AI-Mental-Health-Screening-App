package com.mindease.backend.features.physical.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * Unit conversion is the boundary between human input and canonical storage.
 * Unknown units must be rejected, never guessed — a wrong guess would silently
 * corrupt a health record.
 */
class LifestyleUnitsTest {

    private final LifestyleUnits units = new LifestyleUnits();

    @Test
    void hydration_acceptsCommonUnits() {
        assertThat(units.hydrationToMl(250d, "ml")).isEqualTo(250d);
        assertThat(units.hydrationToMl(1d, "l")).isEqualTo(1000d);
        assertThat(units.hydrationToMl(1d, "cup")).isEqualTo(240d);
        assertThat(units.hydrationToMl(8d, "fl oz")).isCloseTo(236.6d,
                org.assertj.core.data.Offset.offset(0.1d));
        // Missing unit defaults to millilitres rather than failing silently.
        assertThat(units.hydrationToMl(300d, null)).isEqualTo(300d);
    }

    @Test
    void hydration_rejectsUnknownUnitAndOversizedEntry() {
        assertThatThrownBy(() -> units.hydrationToMl(1d, "bucket"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Unsupported hydration unit");
        assertThatThrownBy(() -> units.hydrationToMl(6000d, "ml"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("5000 ml");
        assertThatThrownBy(() -> units.hydrationToMl(-5d, "ml"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void weight_convertsImperialToKilograms() {
        assertThat(units.weightToKg(70d, "kg")).isEqualTo(70d);
        assertThat(units.weightToKg(154.324d, "lb")).isCloseTo(70d,
                org.assertj.core.data.Offset.offset(0.01d));
        assertThat(units.weightToKg(11d, "st")).isCloseTo(69.85d,
                org.assertj.core.data.Offset.offset(0.01d));
    }

    @Test
    void weight_rejectsOutOfRangeValues() {
        assertThatThrownBy(() -> units.weightToKg(600d, "kg"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("2 and 500");
        assertThatThrownBy(() -> units.weightToKg(Double.NaN, "kg"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void height_convertsImperialToCentimetres() {
        assertThat(units.heightToCm(180d, "cm")).isEqualTo(180d);
        assertThat(units.heightToCm(1.8d, "m")).isEqualTo(180d);
        assertThat(units.heightToCm(70d, "in")).isCloseTo(177.8d,
                org.assertj.core.data.Offset.offset(0.01d));
        assertThat(units.heightToCm(5.9d, "ft")).isCloseTo(179.8d,
                org.assertj.core.data.Offset.offset(0.01d));
    }

    @Test
    void bmiCategoriesUseNeutralReferenceWording() {
        assertThat(units.bmiCategory(17d)).isEqualTo("BELOW_REFERENCE_RANGE");
        assertThat(units.bmiCategory(22d)).isEqualTo("REFERENCE_RANGE");
        assertThat(units.bmiCategory(27d)).isEqualTo("ABOVE_REFERENCE_RANGE");
        assertThat(units.bmiCategory(33d)).isEqualTo("WELL_ABOVE_REFERENCE_RANGE");
        // Labels must not read as a diagnosis.
        assertThat(units.bmiLabel("REFERENCE_RANGE")).contains("reference range");
        assertThat(units.bmiLabel("WELL_ABOVE_REFERENCE_RANGE"))
                .doesNotContainIgnoringCase("disease");
    }
}
