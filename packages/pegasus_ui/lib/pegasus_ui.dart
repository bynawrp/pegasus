/// Thème et composants visuels partagés Pegasus (voir docs/design/).
library;

import 'package:flutter/material.dart';

/// Palette Pegasus (thème sombre par défaut).
abstract final class PegasusColors {
  static const background = Color(0xFF0D1017);
  static const surface = Color(0xFF161B24);
  static const surfaceHigh = Color(0xFF1F2632);
  static const border = Color(0xFF2A3341);
  static const text = Color(0xFFE8ECF2);
  static const textMuted = Color(0xFF9AA4B2);
  static const accent = Color(0xFF8AB4FF);
  static const danger = Color(0xFFFF8A7A);
  static const success = Color(0xFF5BD69A);
  static const warning = Color(0xFFF2C179);
}

/// Thèmes Material construits sur la palette Pegasus.
abstract final class PegasusTheme {
  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: PegasusColors.accent,
      onPrimary: PegasusColors.background,
      surface: PegasusColors.surface,
      onSurface: PegasusColors.text,
      error: PegasusColors.danger,
      outline: PegasusColors.border,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: PegasusColors.background,
      dividerColor: PegasusColors.border,
    );
  }
}
