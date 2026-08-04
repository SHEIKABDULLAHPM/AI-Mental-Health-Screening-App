import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color seed = Color(0xFF2E9E8B);

  static const Color primary = Color(0xFF2E9E8B);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFCFF3EC);
  static const Color onPrimaryContainer = Color(0xFF063D35);

  static const Color secondary = Color(0xFF8A8FD8);
  static const Color secondaryContainer = Color(0xFFE5E7FA);
  static const Color onSecondaryContainer = Color(0xFF23265A);

  static const Color gradientStart = Color(0xFF2E9E8B);
  static const Color gradientEnd = Color(0xFF5FBF9E);
  static const Color gradientAccent = Color(0xFF8A8FD8);

  static const Color backgroundLight = Color(0xFFF6FAF8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color backgroundDark = Color(0xFF0D1413);
  static const Color surfaceDark = Color(0xFF16201E);

  static const Color textPrimaryLight = Color(0xFF1A2724);
  static const Color textSecondaryLight = Color(0xFF5C6B67);
  static const Color textPrimaryDark = Color(0xFFE6EFEC);
  static const Color textSecondaryDark = Color(0xFFA3B3AF);

  static const Color success = Color(0xFF2FA46B);
  static const Color warning = Color(0xFFE0A03E);
  static const Color danger = Color(0xFFD65C6E);
  static const Color info = Color(0xFF4A7BD0);

  static const Color shadow = Color(0x140B2B24);
  static const Color outlineSoftLight = Color(0x1A0B2B24);
  static const Color outlineSoftDark = Color(0x24FFFFFF);

  static Color scoreColor(double score) {
    if (score >= 75) return success;
    if (score >= 50) return warning;
    return danger;
  }
}
