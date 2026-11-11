import 'package:flutter/material.dart';

/// Palettes disponibles. [neon] est la palette par défaut ;
/// les autres sont proposées dans les réglages de l'app et de l'agent.
enum PegasusPalette {
  neon('Néon', 'Magenta + cyan'),
  acide('Acide', 'Vert acide + violet'),
  braise('Braise', 'Orange + or'),
  glace('Glace', 'Bleu électrique + cyan'),
  toxique('Toxique', 'Violet + vert acide'),
  rouge('Rouge & or', 'Rouge vif + or');

  const PegasusPalette(this.label, this.description);

  final String label;
  final String description;

  static const PegasusPalette defaultPalette = PegasusPalette.neon;
}

/// Jeu de couleurs d'une palette pour une luminosité donnée.
///
/// Disponible dans l'arbre via `Theme.of(context).extension<PegasusColors>()`.
@immutable
class PegasusColors extends ThemeExtension<PegasusColors> {
  const PegasusColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accent2,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color line;
  final Color text;
  final Color textMuted;

  /// Couleur principale (actions, sélection, halo néon).
  final Color accent;

  /// Couleur secondaire (logo, graphiques, éléments complémentaires).
  final Color accent2;
  final Color success;
  final Color warning;
  final Color danger;

  /// Couleurs d'une [palette] en thème sombre ou clair.
  static PegasusColors of(PegasusPalette palette, Brightness brightness) =>
      _palettes[palette]![brightness]!;

  @override
  PegasusColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? line,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? accent2,
    Color? success,
    Color? warning,
    Color? danger,
  }) =>
      PegasusColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        line: line ?? this.line,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        accent2: accent2 ?? this.accent2,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
      );

  @override
  PegasusColors lerp(PegasusColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PegasusColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      line: l(line, other.line),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
    );
  }
}

PegasusColors _c(List<int> v) => PegasusColors(
      background: Color(v[0]),
      surface: Color(v[1]),
      surfaceHigh: Color(v[2]),
      line: Color(v[3]),
      text: Color(v[4]),
      textMuted: Color(v[5]),
      accent: Color(v[6]),
      accent2: Color(v[7]),
      success: Color(v[8]),
      warning: Color(v[9]),
      danger: Color(v[10]),
    );

// Ordre : fond, surface, surface haute, ligne, texte, texte secondaire,
// accent, accent 2, succès, alerte, danger.
final Map<PegasusPalette, Map<Brightness, PegasusColors>> _palettes = {
  PegasusPalette.neon: {
    Brightness.dark: _c([0xFF0B0614, 0xFF140C24, 0xFF1D1233, 0xFF3A2366, 0xFFF5F0FF, 0xFFB8AAD8, 0xFFFF2E88, 0xFF2EF2FF, 0xFF3CFF8F, 0xFFFFE14D, 0xFFFF4D4D]),
    Brightness.light: _c([0xFFF6F2FF, 0xFFFFFFFF, 0xFFEEE7FF, 0xFFD6C8F5, 0xFF1A0F2E, 0xFF584A78, 0xFFC8006A, 0xFF00798A, 0xFF0E7A3F, 0xFF8A6A00, 0xFFB3122E]),
  },
  PegasusPalette.acide: {
    Brightness.dark: _c([0xFF070A06, 0xFF10140D, 0xFF171D12, 0xFF2F3D22, 0xFFF2FFE6, 0xFFAABA9A, 0xFFB6FF3B, 0xFF9B6BFF, 0xFF7CFFB2, 0xFFFFE14D, 0xFFFF5470]),
    Brightness.light: _c([0xFFF5FAEF, 0xFFFFFFFF, 0xFFEAF3E0, 0xFFCFE0BC, 0xFF12180C, 0xFF4E5C40, 0xFF3F7A00, 0xFF6B3FD6, 0xFF13784A, 0xFF8A6A00, 0xFFB3122E]),
  },
  PegasusPalette.braise: {
    Brightness.dark: _c([0xFF0D0705, 0xFF1A0E09, 0xFF24130C, 0xFF4A2414, 0xFFFFF1EA, 0xFFCDA796, 0xFFFF6B2C, 0xFFFFB02E, 0xFF4DFF9A, 0xFFFFD84D, 0xFFFF3D5A]),
    Brightness.light: _c([0xFFFFF5F0, 0xFFFFFFFF, 0xFFFFE9DE, 0xFFF3C9B3, 0xFF2A120A, 0xFF74493A, 0xFFC2410C, 0xFF8F5A00, 0xFF13784A, 0xFF8A6100, 0xFFB3122E]),
  },
  PegasusPalette.glace: {
    Brightness.dark: _c([0xFF03060F, 0xFF0A1124, 0xFF101A33, 0xFF1F3266, 0xFFEEF4FF, 0xFFA6B5D8, 0xFF2F7BFF, 0xFF3CF0FF, 0xFF3CFF9A, 0xFFFFD84D, 0xFFFF4D6A]),
    Brightness.light: _c([0xFFF0F5FF, 0xFFFFFFFF, 0xFFE3ECFF, 0xFFC4D4F5, 0xFF0A1430, 0xFF45577E, 0xFF1F5FD6, 0xFF00788A, 0xFF13784A, 0xFF8A6A00, 0xFFB3122E]),
  },
  PegasusPalette.toxique: {
    Brightness.dark: _c([0xFF090512, 0xFF130A22, 0xFF1B1030, 0xFF35205A, 0xFFF6EEFF, 0xFFB9A8D6, 0xFFA855FF, 0xFFC6FF3D, 0xFF3CFF8F, 0xFFFFE14D, 0xFFFF4D6A]),
    Brightness.light: _c([0xFFF7F2FF, 0xFFFFFFFF, 0xFFEFE6FF, 0xFFD9C9F2, 0xFF1C0F33, 0xFF574A72, 0xFF7A2FD6, 0xFF4C7A00, 0xFF13784A, 0xFF8A6A00, 0xFFB3122E]),
  },
  PegasusPalette.rouge: {
    Brightness.dark: _c([0xFF0B0505, 0xFF170A0B, 0xFF211012, 0xFF4A1E22, 0xFFFFF0F0, 0xFFCEA5A8, 0xFFFF2E4D, 0xFFFFC23D, 0xFF3CFF8F, 0xFFFFC23D, 0xFFFF7A3D]),
    Brightness.light: _c([0xFFFFF4F4, 0xFFFFFFFF, 0xFFFFE5E7, 0xFFF2C3C8, 0xFF2A0A0E, 0xFF74404A, 0xFFC8102E, 0xFF8A6400, 0xFF13784A, 0xFF8A6400, 0xFFB33A00]),
  },
};
