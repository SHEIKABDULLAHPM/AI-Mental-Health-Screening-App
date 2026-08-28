package com.mindease.backend.coach.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;

import com.mindease.backend.common.error.ApiException;
import com.mindease.backend.coach.domain.Conversation;
import com.mindease.backend.coach.domain.ConversationRepository;
import com.mindease.backend.coach.domain.Message;
import com.mindease.backend.coach.domain.MessageRepository;
import com.mindease.backend.coach.dto.CreateConversationRequest;
import com.mindease.backend.coach.dto.SendMessageRequest;

@ExtendWith(MockitoExtension.class)
class ConversationServiceTest {

    @Mock
    private ConversationRepository conversationRepo;

    @Mock
    private MessageRepository messageRepo;

    private ConversationService service;

    private static final String USER_ID = "user-1";
    private static final String CONVERSATION_ID = "conv-1";
    private static final String OTHER_USER_ID = "other-user";

    @BeforeEach
    void setUp() {
        service = new ConversationService(conversationRepo, messageRepo);
    }

    // ── Conversation CRUD ──

    @Test
    void createConversation_success() {
        when(conversationRepo.save(any())).thenAnswer(inv -> {
            Conversation c = inv.getArgument(0);
            c.setId(CONVERSATION_ID);
            return c;
        });

        var response = service.createConversation(USER_ID, new CreateConversationRequest("Test"));

        assertThat(response.id()).isEqualTo(CONVERSATION_ID);
        assertThat(response.title()).isEqualTo("Test");
        verify(conversationRepo).save(any());
    }

    @Test
    void createConversation_defaultTitle() {
        when(conversationRepo.save(any())).thenAnswer(inv -> {
            Conversation c = inv.getArgument(0);
            c.setId(CONVERSATION_ID);
            return c;
        });

        var response = service.createConversation(USER_ID, new CreateConversationRequest(null));

        assertThat(response.title()).isEqualTo("New conversation");
    }

    @Test
    void getConversations_returnsList() {
        List<Conversation> conversations = List.of(
                buildConversation("c1", USER_ID, "Chat 1"),
                buildConversation("c2", USER_ID, "Chat 2"));
        when(conversationRepo.findByUserIdOrderByUpdatedAtDesc(any(String.class), any(Pageable.class)))
                .thenReturn(conversations);

        var result = service.getConversations(USER_ID, 0, 20);

        assertThat(result).hasSize(2);
        assertThat(result.get(0).title()).isEqualTo("Chat 1");
    }

    @Test
    void getConversation_found() {
        Conversation c = buildConversation(CONVERSATION_ID, USER_ID, "My Chat");
        when(conversationRepo.findByIdAndUserId(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.of(c));

        var response = service.getConversation(USER_ID, CONVERSATION_ID);

        assertThat(response.title()).isEqualTo("My Chat");
    }

    @Test
    void getConversation_notFound_throws() {
        when(conversationRepo.findByIdAndUserId(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getConversation(USER_ID, CONVERSATION_ID))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void deleteConversation_removesMessagesAndConversation() {
        Conversation c = buildConversation(CONVERSATION_ID, USER_ID, "To Delete");
        when(conversationRepo.findByIdAndUserId(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.of(c));

        service.deleteConversation(USER_ID, CONVERSATION_ID);

        verify(messageRepo).deleteByConversationIdAndUserId(CONVERSATION_ID, USER_ID);
        verify(conversationRepo).deleteById(CONVERSATION_ID);
    }

    // ── Message CRUD ──

    @Test
    void storeUserMessage_success() {
        Conversation c = buildConversation(CONVERSATION_ID, USER_ID, "Chat");
        when(conversationRepo.findByIdAndUserId(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.of(c));
        when(messageRepo.findTopByConversationIdAndUserIdOrderBySequenceDesc(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.empty());
        when(messageRepo.save(any())).thenAnswer(inv -> {
            Message m = inv.getArgument(0);
            m.setId("msg-1");
            return m;
        });
        when(conversationRepo.save(any())).thenReturn(c);

        Message result = service.storeUserMessage(
                USER_ID, CONVERSATION_ID,
                new SendMessageRequest("Hello", null));

        assertThat(result.getRole()).isEqualTo("user");
        assertThat(result.getContent()).isEqualTo("Hello");
        assertThat(result.getSequence()).isEqualTo(1);
    }

    @Test
    void storeUserMessage_idempotent() {
        Message existing = new Message();
        existing.setId("existing-msg");
        existing.setClientMessageId("client-123");
        when(messageRepo.findByClientMessageIdAndUserId("client-123", USER_ID))
                .thenReturn(Optional.of(existing));

        Message result = service.storeUserMessage(
                USER_ID, CONVERSATION_ID,
                new SendMessageRequest("Hello", "client-123"));

        assertThat(result.getId()).isEqualTo("existing-msg");
        verify(messageRepo, never()).save(any());
    }

    @Test
    void storeUserMessage_conversationNotFound_throws() {
        when(conversationRepo.findByIdAndUserId(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.storeUserMessage(
                USER_ID, CONVERSATION_ID,
                new SendMessageRequest("Hello", null)))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void getMessages_conversationNotFound_throws() {
        when(conversationRepo.findByIdAndUserId(CONVERSATION_ID, USER_ID))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getMessages(USER_ID, CONVERSATION_ID))
                .isInstanceOf(ApiException.class);
    }

    // ── Helpers ──

    private static Conversation buildConversation(String id, String userId, String title) {
        Conversation c = new Conversation();
        c.setId(id);
        c.setUserId(userId);
        c.setTitle(title);
        c.setMessageCount(0);
        c.setSafetyState("NORMAL");
        c.setCreatedAt(Instant.now());
        c.setUpdatedAt(Instant.now());
        return c;
    }
}
