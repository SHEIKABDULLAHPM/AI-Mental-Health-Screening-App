import 'package:flutter/material.dart';

/// Design tokens: brand colors for light & dark modes.
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF4F6DF5);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFE2E8FF);
  static const Color onPrimaryContainer = Color(0xFF12215B);

  static const Color secondary = Color(0xFF6EC6FF);
  static const Color onSecondary = Color(0xFF0A2A3D);
  static const Color secondaryContainer = Color(0xFFE1F3FF);
  static const Color onSecondaryContainer = Color(0xFF0F3A52);

  static const Color tertiary = Color(0xFF8B8EE8);
  static const Color tertiaryContainer = Color(0xFFE8E9FF);
  static const Color onTertiaryContainer = Color(0xFF1F2060);

  static const Color accent = Color(0xFF7EE0A3);
  static const Color accentContainer = Color(0xFFDDF7E7);
  static const Color onAccentContainer = Color(0xFF0E3D22);

  // Gradients
  static const Color gradientStart = Color(0xFF4F6DF5);
  static const Color gradientEnd = Color(0xFF7EA6FF);
  static const Color gradientAccent = Color(0xFF6EC6FF);

  // Surfaces
  static const Color backgroundLight = Color(0xFFF5F7FD);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceAltLight = Color(0xFFEDF1FA);

  static const Color backgroundDark = Color(0xFF0E1220);
  static const Color surfaceDark = Color(0xFF161C30);
  static const Color surfaceAltDark = Color(0xFF1D2440);

  // Text
  static const Color textPrimaryLight = Color(0xFF171A26);
  static const Color textSecondaryLight = Color(0xFF5E6475);
  static const Color textTertiaryLight = Color(0xFF8A90A2);

  static const Color textPrimaryDark = Color(0xFFE9EBF5);
  static const Color textSecondaryDark = Color(0xFFA6ADC4);
  static const Color textTertiaryDark = Color(0xFF767E9A);

  // Semantic
  static const Color success = Color(0xFF30A46C);
  static const Color successContainer = Color(0xFFD8F0E2);
  static const Color warning = Color(0xFFFFB020);
  static const Color warningContainer = Color(0xFFFCEFCF);
  static const Color error = Color(0xFFE5484D);
  static const Color errorContainer = Color(0xFFFADFE0);
  static const Color info = Color(0xFF4A7BD0);

  // Helpers
  static const Color shadow = Color(0x140F1B4D);
  static const Color outlineLight = Color(0x1A12152A);
  static const Color outlineDark = Color(0x26FFFFFF);

  /// Returns a cheerful colour for a wellness score (0-100).
  static Color scoreColor(double score) {
    if (score >= 75) return success;
    if (score >= 50) return warning;
    return error;
  }
}
