import 'package:equatable/equatable.dart';

class ScreeningSubmission extends Equatable {
  const ScreeningSubmission({
    required this.userId,
    required this.questionnaireType,
    required this.answers,
  });

  final String userId;
  final String questionnaireType;
  final Map<String, int> answers;

  @override
  List<Object?> get props => [userId, questionnaireType, answers];
}
