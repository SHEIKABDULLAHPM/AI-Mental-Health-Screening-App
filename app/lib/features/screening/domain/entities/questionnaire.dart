import 'package:equatable/equatable.dart';

class Questionnaire extends Equatable {
  const Questionnaire({
    required this.id,
    required this.title,
    required this.scale,
    required this.questions,
  });

  final String id;
  final String title;
  final String scale;
  final List<String> questions;

  @override
  List<Object?> get props => [id, title, scale, questions];
}
