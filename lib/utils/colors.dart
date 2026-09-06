import 'package:flutter/material.dart';

class AppColors {
  // Primary brand
  static const Color primary     = Color(0xFF6C3CE1);   // rich violet
  static const Color primaryDark = Color(0xFF4A1FA8);
  static const Color accent      = Color(0xFFFF6B6B);   // coral accent
  static const Color gold        = Color(0xFFFFD700);
  static const Color teal        = Color(0xFF00C9A7);

  // Backgrounds
  static const Color bgDark      = Color(0xFF0A0A14);
  static const Color bgCard      = Color(0xFF12121F);
  static const Color surface     = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFFF8F6FF);

  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color white       = Colors.white;

  // Gradients
  static const List<Color> primaryGradient  = [Color(0xFF6C3CE1), Color(0xFFB06AB3)];
  static const List<Color> accentGradient   = [Color(0xFFFF6B6B), Color(0xFFFFA500)];
  static const List<Color> darkGradient     = [Color(0xFF0A0A14), Color(0xFF1A1A2E)];
  static const List<Color> glassGradient    = [Color(0xFF6C3CE1), Color(0xFFB06AB3), Color(0xFFFF6B6B)];
}
