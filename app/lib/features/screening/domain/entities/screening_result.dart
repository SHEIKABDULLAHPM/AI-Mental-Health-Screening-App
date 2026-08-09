import 'package:equatable/equatable.dart';

/// Result of a completed screening (PHQ-9, GAD-7, ...).
class ScreeningResult extends Equatable {
  const ScreeningResult({
    required this.id,
    required this.questionnaireType,
    required this.totalScore,
  });

  final String id;
  final String questionnaireType;
  final int totalScore;

  @override
  List<Object?> get props => [id, questionnaireType, totalScore];
}
