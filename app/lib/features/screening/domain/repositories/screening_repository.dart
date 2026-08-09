import 'dart:async';

import 'package:mindease/features/screening/domain/entities/questionnaire.dart';
import 'package:mindease/features/screening/domain/entities/screening_result.dart';
import 'package:mindease/features/screening/domain/entities/screening_submission.dart';

/// Screening feature contract (domain layer).
abstract class ScreeningRepository {
  Future<List<Questionnaire>> getQuestionnaires();
  Future<ScreeningResult> submit(ScreeningSubmission submission);
  Future<List<ScreeningResult>> getMyResults();
}
