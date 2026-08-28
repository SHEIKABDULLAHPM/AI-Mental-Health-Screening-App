package com.mindease.backend.coach.domain;

import java.util.List;
import java.util.Optional;

import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;

public interface MessageRepository extends MongoRepository<Message, String> {

    List<Message> findByConversationIdAndUserIdOrderBySequenceAsc(
            String conversationId, String userId, Pageable pageable);

    List<Message> findByConversationIdAndUserIdOrderBySequenceDesc(
            String conversationId, String userId, Pageable pageable);

    Optional<Message> findByIdAndUserId(String id, String userId);

    Optional<Message> findByClientMessageIdAndUserId(String clientMessageId, String userId);

    Optional<Message> findTopByConversationIdAndUserIdOrderBySequenceDesc(
            String conversationId, String userId);

    long countByConversationIdAndUserId(String conversationId, String userId);

    void deleteByConversationIdAndUserId(String conversationId, String userId);

    /** Get the N most recent messages for context (reversed to chronological). */
    default List<Message> findRecentMessages(String conversationId, String userId, int limit) {
        List<Message> recent = findByConversationIdAndUserIdOrderBySequenceDesc(
                conversationId, userId, Pageable.ofSize(limit));
        return recent.reversed();
    }
}
