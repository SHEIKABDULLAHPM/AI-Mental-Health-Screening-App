import 'dart:async';

import 'package:mindease/features/support/domain/entities/support_resource.dart';

/// Support & guidance feature contract (domain layer).
abstract class SupportRepository {
  Future<SupportResource> getRecommendedSupport(String userId);
  Future<List<SupportResource>> crisisResources();
}
