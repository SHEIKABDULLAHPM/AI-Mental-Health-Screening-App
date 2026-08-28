package com.mindease.backend.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * Fails startup when the shared internal API key is unset or still the dev
 * placeholder outside the {@code dev} and {@code test} profiles. A blank or
 * well-known key would let anyone who can reach the backend claim, complete or
 * fail arbitrary AI jobs - so production must never boot with one.
 */
@Component
public class InternalKeyStartupValidator implements ApplicationRunner {

    public static final String PLACEHOLDER = "change-me-dev-internal-key";

    private static final Logger log = LoggerFactory.getLogger(InternalKeyStartupValidator.class);

    private final AppProperties props;
    private final String[] activeProfiles;

    public InternalKeyStartupValidator(AppProperties props,
                                       @Value("${spring.profiles.active:}") String activeProfiles) {
        this.props = props;
        this.activeProfiles = activeProfiles == null ? new String[0]
                : activeProfiles.split(",");
    }

    @Override
    public void run(ApplicationArguments args) {
        String key = props.getAi().getInternalApiKey();
        if (isDevOrTest()) {
            if (key == null || key.isBlank()) {
                throw new IllegalStateException(
                        "AI_INTERNAL_API_KEY must be set (shared by backend and AI service).");
            }
            log.debug("internal_api_key_configured (dev/test profile)");
            return;
        }
        if (key == null || key.isBlank() || key.equals(PLACEHOLDER)) {
            throw new IllegalStateException(
                    "AI_INTERNAL_API_KEY must be set to a strong, unique secret. The "
                            + "placeholder '" + PLACEHOLDER + "' and unset values are rejected "
                            + "outside the dev/test profiles.");
        }
        log.info("internal_api_key_configured (production profile)");
    }

    private boolean isDevOrTest() {
        for (String profile : activeProfiles) {
            String p = profile == null ? "" : profile.trim();
            if (p.equals("dev") || p.equals("test")) {
                return true;
            }
        }
        return false;
    }
}