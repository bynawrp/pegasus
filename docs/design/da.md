# Direction artistique — décision

> Issue : #40 · Date : 2026-11-11

## Choix : Gaming / néon

Maquette (univers, palettes, logos) : https://claude.ai/artifact/59ZC8pejpJDAyeSHCK7yYG

Pistes écartées : IA holographique (trop futuriste), minimal, mythologie / constellation, verre.

## Thèmes

- **Palette par défaut : Néon** (magenta `#FF2E88` + cyan `#2EF2FF`), **thème sombre**.
- L'utilisateur peut choisir dans les réglages (app et agent) :
  - la **palette** : Néon, Acide, Braise, Glace, Toxique, Rouge & or ;
  - le **mode** : sombre, clair (ou suivre le système).
- Chaque palette existe en sombre et en clair ; les contrastes texte/fond sont vérifiés automatiquement (≥ 4.5:1) dans les tests de `pegasus_ui`.

| Palette | Accent | Accent 2 |
|---|---|---|
| Néon (défaut) | `#FF2E88` magenta | `#2EF2FF` cyan |
| Acide | `#B6FF3B` vert acide | `#9B6BFF` violet |
| Braise | `#FF6B2C` orange | `#FFB02E` or |
| Glace | `#2F7BFF` bleu électrique | `#3CF0FF` cyan |
| Toxique | `#A855FF` violet | `#C6FF3D` vert acide |
| Rouge & or | `#FF2E4D` rouge | `#FFC23D` or |

(Valeurs du thème sombre ; les variantes claires sont assombries pour rester lisibles.)

## Typographie (embarquée, licence OFL)

| Usage | Police |
|---|---|
| Titres | **Barlow Condensed** 600/700, en majuscules dans l'interface |
| Texte | **Barlow** 400/500/600 |
| Chiffres, données | **JetBrains Mono** |

## Formes et effets

- Arrondis : cartes 12 px, contrôles 8 px, fenêtres 10 px.
- Halo néon sur les éléments actifs (bouton principal, sélection) et halo discret sur les cartes, **en thème sombre uniquement**.
- Fond de l'app : léger quadrillage aux couleurs de l'accent 2.
- Icônes au trait (1,8 px), coins arrondis.

## Logo

Pégase en **silhouette pleine** : tête et cou trapus, aile à trois plumes.
- Corps : accent ; aile : accent 2 ; l'œil est découpé dans la couleur de fond.
- Fichier : `packages/pegasus_ui/assets/logo/pegasus.svg` (version Néon).
- À faire avant publication : finaliser le tracé (version vectorielle propre, déclinaisons icône d'app iOS/Android/Windows).

## Implémentation

`packages/pegasus_ui` :
- `PegasusPalette` (6 palettes) et `PegasusColors.of(palette, brightness)`, aussi disponible en `ThemeExtension` ;
- `PegasusTheme.build(palette:, brightness:)` → `ThemeData` complet ;
- `PegasusFonts`, `PegasusRadii`, `PegasusSizes`, `PegasusEffects` (halos), `PegasusAssets.logoSvg`.
