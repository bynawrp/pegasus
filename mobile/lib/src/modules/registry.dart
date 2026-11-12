import 'package:flutter/material.dart';

import '../home/home_layout.dart';
import 'keyboard/keyboard_module.dart';
import 'trackpad/trackpad_module.dart';

enum ModuleCategory {
  control('Contrôle'),
  media('Médias'),
  system('Système'),
  apps('Applications'),
  files('Fichiers'),
  automation('Automatisation'),
  devices('Appareils');

  const ModuleCategory(this.label);
  final String label;
}

enum ModuleTier { mvp, v2, v3 }

/// Un module = une fonctionnalité (docs/design/mobile.md, « Registre des modules »).
class PegasusModule {
  const PegasusModule({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.tier,
    this.permission,
    this.sizes = const [],
    this.defaultSize,
    this.screen,
    this.widget,
  });

  final String id;
  final String name;
  final IconData icon;
  final ModuleCategory category;
  final ModuleTier tier;

  /// Module de permission côté agent (`input`, `media`…), `null` si aucun.
  final String? permission;

  /// Tailles de widget proposées (vide : pas de widget d'accueil).
  final List<WidgetSize> sizes;
  final WidgetSize? defaultSize;

  /// Écran plein du module.
  final WidgetBuilder? screen;

  /// Widget d'accueil pour une taille donnée.
  final Widget Function(BuildContext context, WidgetSize size)? widget;

  /// Disponible dans cette version de l'app.
  bool get available => screen != null;
}

/// Tous les modules, disponibles ou à venir. Ajouter une fonctionnalité =
/// ajouter une entrée ici ; accueil, catalogue et galerie la récupèrent.
final List<PegasusModule> moduleRegistry = [
  trackpadModule,
  keyboardModule,
  const PegasusModule(id: 'gamepad', name: 'Manette', icon: Icons.sports_esports_rounded, category: ModuleCategory.control, tier: ModuleTier.v3),
  const PegasusModule(id: 'media', name: 'Lecture', icon: Icons.play_circle_outline_rounded, category: ModuleCategory.media, tier: ModuleTier.mvp),
  const PegasusModule(id: 'mixer', name: 'Mixeur audio', icon: Icons.tune_rounded, category: ModuleCategory.media, tier: ModuleTier.v2),
  const PegasusModule(id: 'power', name: 'Alimentation', icon: Icons.power_settings_new_rounded, category: ModuleCategory.system, tier: ModuleTier.mvp),
  const PegasusModule(id: 'monitor', name: 'Surveillance', icon: Icons.monitor_heart_outlined, category: ModuleCategory.system, tier: ModuleTier.v2),
  const PegasusModule(id: 'display', name: 'Écran', icon: Icons.brightness_6_rounded, category: ModuleCategory.system, tier: ModuleTier.v2),
  const PegasusModule(id: 'favorites', name: 'Favoris', icon: Icons.apps_rounded, category: ModuleCategory.apps, tier: ModuleTier.mvp),
  const PegasusModule(id: 'windows', name: 'Fenêtres', icon: Icons.web_asset_rounded, category: ModuleCategory.apps, tier: ModuleTier.v2),
  const PegasusModule(id: 'processes', name: 'Processus', icon: Icons.memory_rounded, category: ModuleCategory.apps, tier: ModuleTier.v2),
  const PegasusModule(id: 'transfers', name: 'Transferts', icon: Icons.swap_vert_rounded, category: ModuleCategory.files, tier: ModuleTier.v2),
  const PegasusModule(id: 'clipboard', name: 'Presse-papiers', icon: Icons.content_paste_rounded, category: ModuleCategory.files, tier: ModuleTier.v2),
  const PegasusModule(id: 'macros', name: 'Macros', icon: Icons.bolt_rounded, category: ModuleCategory.automation, tier: ModuleTier.v2),
  const PegasusModule(id: 'integrations', name: 'Intégrations', icon: Icons.extension_rounded, category: ModuleCategory.automation, tier: ModuleTier.v3),
  const PegasusModule(id: 'notifications', name: 'Notifications', icon: Icons.notifications_none_rounded, category: ModuleCategory.automation, tier: ModuleTier.v3),
  const PegasusModule(id: 'pcs', name: 'Mes PC', icon: Icons.devices_rounded, category: ModuleCategory.devices, tier: ModuleTier.v2),
  const PegasusModule(id: 'settings', name: 'Réglages', icon: Icons.settings_rounded, category: ModuleCategory.devices, tier: ModuleTier.mvp),
];

PegasusModule? moduleById(String id) => moduleRegistry.where((m) => m.id == id).firstOrNull;

/// Accueil par défaut (premier lancement) : modules du MVP disponibles.
const defaultHomeModules = [('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)];
