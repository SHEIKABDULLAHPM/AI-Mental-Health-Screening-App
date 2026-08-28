package com.mindease.backend.user.api;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mindease.backend.common.api.ApiResponse;
import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.common.error.ErrorCode;
import com.mindease.backend.security.AuthenticatedUser;
import com.mindease.backend.user.domain.UserRepository;
import com.mindease.backend.user.dto.UserProfileDto;

/**
 * Current-account endpoints. Identity always comes from the authenticated
 * principal — never from the URL.
 */
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

    private final UserRepository users;

    public UserController(UserRepository users) {
        this.users = users;
    }

    @GetMapping("/me")
    public ResponseEntity<ApiResponse<UserProfileDto>> me() {
        String userId = AuthenticatedUser.currentId();
        UserProfileDto profile = users.findById(userId)
                .map(UserProfileDto::from)
                .orElseThrow(() -> new ApiException(ErrorCode.UNAUTHORIZED, "Account not found"));
        return ResponseEntity.ok(ApiResponse.ok(profile));
    }
}