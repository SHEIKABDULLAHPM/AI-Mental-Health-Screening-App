/// A single journal entry with media and AI analysis support.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.type,
    this.emotion,
    // Media
    this.imageKey,
    this.imageContentType,
    this.imageSize,
    this.imageUrl,
    this.audioKey,
    this.audioContentType,
    this.audioSize,
    this.audioDurationSeconds,
    this.audioUrl,
    this.videoKey,
    this.videoContentType,
    this.videoSize,
    this.videoDurationSeconds,
    this.videoUrl,
    // AI analysis
    this.aiAnalysis,
    // Versioning
    this.contentVersion = 1,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final DateTime date;
  final JournalEntryType type;
  final String? emotion;

  // Media references
  final String? imageKey;
  final String? imageContentType;
  final int? imageSize;
  final String? imageUrl;
  final String? audioKey;
  final String? audioContentType;
  final int? audioSize;
  final int? audioDurationSeconds;
  final String? audioUrl;
  final String? videoKey;
  final String? videoContentType;
  final int? videoSize;
  final int? videoDurationSeconds;
  final String? videoUrl;

  // AI analysis
  final AiAnalysisData? aiAnalysis;

  // Versioning
  final int contentVersion;
  final DateTime? updatedAt;

  bool get hasImage => imageKey != null && imageKey!.isNotEmpty;
  bool get hasAudio => audioKey != null && audioKey!.isNotEmpty;
  bool get hasVideo => videoKey != null && videoKey!.isNotEmpty;

  String get dateLabel {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String get timeLabel {
    final h = date.hour;
    final m = date.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour:$m $period';
  }

  String get audioDurationLabel {
    if (audioDurationSeconds == null) return '';
    final min = audioDurationSeconds! ~/ 60;
    final sec = audioDurationSeconds! % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

/// AI analysis data embedded in a journal entry.
class AiAnalysisData {
  const AiAnalysisData({
    required this.status,
    this.emotion,
    this.emotionConfidence,
    this.sentiment,
    this.sentimentConfidence,
    this.emotionalThemes,
    this.summary,
    this.reflectionPrompt,
  });

  final String status;
  final String? emotion;
  final double? emotionConfidence;
  final String? sentiment;
  final double? sentimentConfidence;
  final String? emotionalThemes;
  final String? summary;
  final String? reflectionPrompt;

  bool get isReady => status == 'COMPLETED';
  bool get isStale => status == 'STALE';
  bool get isProcessing => status == 'PROCESSING';
  bool get hasFailed =>
      status == 'FAILED' || status == 'TIMEOUT' || status == 'UNAVAILABLE';
}

enum JournalEntryType { text, voice, image, video }

extension JournalEntryTypeX on JournalEntryType {
  String get label => switch (this) {
        JournalEntryType.text => 'Text',
        JournalEntryType.voice => 'Voice',
        JournalEntryType.image => 'Image',
        JournalEntryType.video => 'Video',
      };

  bool get isText => this == JournalEntryType.text;
}
