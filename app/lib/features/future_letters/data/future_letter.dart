import 'package:flutter/material.dart';

/// A letter you write today, delivered to yourself (or someone) later.
class FutureLetter {
  const FutureLetter({
    required this.id,
    required this.title,
    required this.recipient,
    required this.scheduledDate,
    required this.content,
    required this.status,
  });

  final String id;
  final String title;
  final String recipient;
  final DateTime scheduledDate;
  final String content;
  final LetterStatus status;
}

enum LetterStatus { scheduled, delivered, opened }

extension LetterStatusX on LetterStatus {
  String get label => switch (this) {
        LetterStatus.scheduled => 'Scheduled',
        LetterStatus.delivered => 'Delivered',
        LetterStatus.opened => 'Opened',
      };

  IconData get icon => switch (this) {
        LetterStatus.scheduled => Icons.schedule_rounded,
        LetterStatus.delivered => Icons.mark_email_read_rounded,
        LetterStatus.opened => Icons.auto_stories_rounded,
      };
}
