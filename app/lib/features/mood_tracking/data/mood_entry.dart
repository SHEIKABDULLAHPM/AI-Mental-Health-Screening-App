/// A single recorded mood snapshot with optional AI observation data.
class MoodEntry {
  const MoodEntry({
    required this.id,
    required this.date,
    required this.moodId,
    required this.emotion,
    required this.note,
    this.source,
    this.confidence,
    this.analysisStatus,
    this.aiObservations = const [],
    this.aiSuggestedMood,
    this.intensity,
  });

  final String id;
  final DateTime date;
  final String moodId;
  final String? emotion;
  final String? note;

  // AI observation fields
  final String? source;
  final double? confidence;
  final String? analysisStatus;
  final List<AiObservation> aiObservations;
  final String? aiSuggestedMood;
  final int? intensity;

  /// Whether this entry has AI analysis attached.
  bool get hasAiData => source != null && source != 'MANUAL';

  /// Hour of day for the entry.
  String get timeLabel {
    final h = date.hour;
    final m = date.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour:$m $period';
  }

  String get dayLabel => '${date.day} ${_monthShort(date.month)}';

  static String _monthShort(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];
}

/// A single AI observation from a specific source.
class AiObservation {
  const AiObservation({
    required this.source,
    required this.emotion,
    required this.confidence,
    this.sentiment,
    this.sentimentConfidence,
    this.suggestedMood,
    this.modelVersion,
  });

  final String source;
  final String emotion;
  final double confidence;
  final String? sentiment;
  final double? sentimentConfidence;
  final String? suggestedMood;
  final String? modelVersion;

  factory AiObservation.fromJson(Map<String, dynamic> json) {
    return AiObservation(
      source: json['source'] as String? ?? '',
      emotion: json['emotion'] as String? ?? 'neutral',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      sentiment: json['sentiment'] as String?,
      sentimentConfidence: (json['sentimentConfidence'] as num?)?.toDouble(),
      suggestedMood: json['suggestedMood'] as String?,
      modelVersion: json['modelVersion'] as String?,
    );
  }
}
