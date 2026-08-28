package com.mindease.backend.config;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;

/**
 * The weak default internal API key must never let production boot; the dev /
 * test profiles keep the easy placeholder for local runs.
 */
class InternalKeyStartupValidatorTest {

    private static final String PROVIDED = "pz8R!sXk2vQm9#cLfA1";

    @Test
    void prodProfileRejectsPlaceholderKey() {
        AppProperties props = propsWith("change-me-dev-internal-key");
        InternalKeyStartupValidator validator = new InternalKeyStartupValidator(props, "prod");

        assertThatThrownBy(() -> validator.run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("AI_INTERNAL_API_KEY");
    }

    @Test
    void prodProfileRejectsBlankKey() {
        InternalKeyStartupValidator validator =
                new InternalKeyStartupValidator(propsWith(""), "prod");

        assertThatThrownBy(() -> validator.run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("AI_INTERNAL_API_KEY");
    }

    @Test
    void prodProfileAcceptsConfiguredKey() {
        InternalKeyStartupValidator validator =
                new InternalKeyStartupValidator(propsWith(PROVIDED), "prod");

        assertThatCode(() -> validator.run(new DefaultApplicationArguments()))
                .doesNotThrowAnyException();
    }

    @Test
    void devProfileAllowsPlaceholderKey() {
        InternalKeyStartupValidator validator =
                new InternalKeyStartupValidator(propsWith("change-me-dev-internal-key"), "dev");

        assertThatCode(() -> validator.run(new DefaultApplicationArguments()))
                .doesNotThrowAnyException();
    }

    @Test
    void devProfileAnEmptyValueIsStillRejected() {
        InternalKeyStartupValidator validator = new InternalKeyStartupValidator(propsWith(""), "dev");

        assertThatThrownBy(() -> validator.run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class);
    }

    private static AppProperties propsWith(String key) {
        AppProperties props = new AppProperties();
        props.getAi().setInternalApiKey(key);
        return props;
    }
}