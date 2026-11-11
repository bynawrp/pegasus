import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';

/// Construction des thèmes Material Pegasus (DA gaming / néon).
abstract final class PegasusTheme {
  /// Thème pour une [palette] et une [brightness] données.
  /// Par défaut : palette Néon, thème sombre.
  static ThemeData build({
    PegasusPalette palette = PegasusPalette.defaultPalette,
    Brightness brightness = Brightness.dark,
  }) {
    final c = PegasusColors.of(palette, brightness);
    final dark = brightness == Brightness.dark;
    final onAccent = dark ? c.background : Colors.white;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: onAccent,
      secondary: c.accent2,
      onSecondary: c.background,
      error: c.danger,
      onError: onAccent,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerHighest: c.surfaceHigh,
      outline: c.line,
      outlineVariant: c.line,
    );

    TextStyle display(double size) => TextStyle(
          fontFamily: PegasusFonts.display,
          package: PegasusFonts.package,
          fontWeight: FontWeight.w700,
          fontSize: size,
          letterSpacing: size * 0.03,
          color: c.text,
        );
    TextStyle body(double size, [FontWeight w = FontWeight.w400]) => TextStyle(
          fontFamily: PegasusFonts.body,
          package: PegasusFonts.package,
          fontWeight: w,
          fontSize: size,
          color: c.text,
        );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(PegasusRadii.control));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      dividerColor: c.line,
      fontFamily: PegasusFonts.body,
      package: PegasusFonts.package,
      extensions: [c],
      textTheme: TextTheme(
        displayLarge: display(44),
        displayMedium: display(36),
        displaySmall: display(30),
        headlineMedium: display(26),
        headlineSmall: display(22),
        titleLarge: display(20),
        titleMedium: body(16, FontWeight.w600),
        titleSmall: body(14, FontWeight.w600),
        bodyLarge: body(16),
        bodyMedium: body(14),
        bodySmall: body(12).copyWith(color: c.textMuted),
        labelLarge: body(14, FontWeight.w600),
        labelMedium: body(12, FontWeight.w500),
        labelSmall: body(11, FontWeight.w500).copyWith(color: c.textMuted),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PegasusRadii.card),
          side: BorderSide(color: c.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: onAccent,
          minimumSize: const Size(PegasusSizes.minTouch, PegasusSizes.minTouch),
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          backgroundColor: c.surfaceHigh,
          side: BorderSide(color: c.line),
          minimumSize: const Size(PegasusSizes.minTouch, PegasusSizes.minTouch),
          shape: controlShape,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceHigh),
        trackOutlineColor: WidgetStateProperty.all(c.line),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.background,
        indicatorColor: c.accent.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.accent : c.textMuted)),
      ),
    );
  }

  /// Raccourci : thème sombre de la palette par défaut.
  static ThemeData dark() => build();
}
