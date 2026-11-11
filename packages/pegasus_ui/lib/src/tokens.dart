import 'package:flutter/material.dart';

/// Familles de polices embarquées dans `pegasus_ui` (licence OFL).
abstract final class PegasusFonts {
  static const package = 'pegasus_ui';

  /// Titres : condensé, en majuscules dans l'interface.
  static const display = 'BarlowCondensed';

  /// Texte courant.
  static const body = 'Barlow';

  /// Chiffres et données.
  static const mono = 'JetBrainsMono';
}

/// Arrondis (px).
abstract final class PegasusRadii {
  static const card = 12.0;
  static const control = 8.0;
  static const window = 10.0;
}

/// Tailles minimales et espacements.
abstract final class PegasusSizes {
  /// Zone tactile minimale.
  static const minTouch = 44.0;
  static const gap = 10.0;
}

/// Effets visuels de la DA gaming / néon.
abstract final class PegasusEffects {
  /// Halo néon autour d'un élément actif (thème sombre uniquement).
  static List<BoxShadow> neonGlow(Color color, Brightness brightness) =>
      brightness == Brightness.dark
          ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 18)]
          : const [];

  /// Halo discret des cartes (thème sombre uniquement).
  static List<BoxShadow> cardGlow(Color accent, Brightness brightness) =>
      brightness == Brightness.dark
          ? [
              BoxShadow(color: accent.withValues(alpha: 0.15), spreadRadius: 1),
              BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 24),
            ]
          : const [];
}

/// Logo Pegasus (pégase silhouette) : `packages/pegasus_ui/assets/logo/pegasus.svg`.
abstract final class PegasusAssets {
  static const logoSvg = 'packages/pegasus_ui/assets/logo/pegasus.svg';
}
