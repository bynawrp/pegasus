import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../../core/providers.dart';
import '../../home/home_layout.dart';
import '../action_feedback.dart';
import '../input/input_service.dart';
import '../module_gate.dart';
import '../registry.dart';

final favoritesModule = PegasusModule(
  id: 'favorites',
  name: 'Favoris',
  icon: Icons.apps_rounded,
  category: ModuleCategory.apps,
  tier: ModuleTier.mvp,
  permission: 'apps',
  sizes: const [WidgetSize.small, WidgetSize.medium, WidgetSize.wide, WidgetSize.large],
  defaultSize: WidgetSize.wide,
  screen: (_) => const FavoritesScreen(),
  widget: (context, size) => FavoritesGrid(
    columns: size == WidgetSize.medium ? 2 : 4,
    rows: size == WidgetSize.large ? 4 : 2,
  ),
);

/// Favoris configurés sur le PC (rechargés à chaque connexion).
final favoriteAppsProvider = FutureProvider<List<FavoriteApp>>((ref) async {
  final link = ref.watch(linkStateProvider);
  if (!link.isConnected) return const [];
  final data = await ref.read(remoteSenderProvider).request('apps.list', const {});
  return [
    for (final raw in (data['apps'] as List? ?? const [])) ?FavoriteApp.fromJson(raw),
  ];
});

Uint8List? _decode(String? icon) {
  if (icon == null) return null;
  try {
    return base64.decode(icon);
  } catch (_) {
    return null;
  }
}

class _AppTile extends ConsumerWidget {
  const _AppTile({required this.app});
  final FavoriteApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final bytes = _decode(app.icon);
    return Material(
      color: c.surfaceHigh,
      borderRadius: BorderRadius.circular(PegasusRadii.control),
      child: InkWell(
        key: ValueKey('fav-${app.id}'),
        borderRadius: BorderRadius.circular(PegasusRadii.control),
        onTap: () => runAction(
          context,
          () => ref.read(remoteSenderProvider).request('apps.launch', {'id': app.id}),
          success: '${app.name} lancé',
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bytes != null)
                  Image.memory(bytes, width: 32, height: 32, gaplessPlayback: true, errorBuilder: (_, _, _) => const Icon(Icons.apps_rounded, size: 32))
                else
                  Icon(Icons.apps_rounded, size: 32, color: c.accent2),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grille fixe de favoris (widget d'accueil) : les premiers favoris.
class FavoritesGrid extends ConsumerWidget {
  const FavoritesGrid({super.key, this.columns = 4, this.rows = 2, this.apps});

  final int columns;
  final int rows;

  /// Liste imposée (une page de l'écran plein), sinon les premiers favoris.
  final List<FavoriteApp>? apps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoriteAppsProvider);
    final all = apps ?? async.value ?? const [];
    final shown = all.take(columns * rows).toList();
    final c = context.pegasus;
    return ModuleGate(
      permission: 'apps',
      compact: true,
      child: apps == null && async.isLoading
          ? const Center(child: CircularProgressIndicator())
          : shown.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Aucun favori. Ajoutez-en dans Pegasus sur le PC (section Favoris).',
                      key: const ValueKey('fav-empty'),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var r = 0; r < rows; r++) ...[
                      if (r > 0) const SizedBox(height: 6),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var col = 0; col < columns; col++) ...[
                              if (col > 0) const SizedBox(width: 6),
                              Expanded(
                                child: r * columns + col < shown.length
                                    ? _AppTile(app: shown[r * columns + col])
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

/// Écran plein : tous les favoris, par pages de 4 × N.
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(favoriteAppsProvider).value ?? const <FavoriteApp>[];
    final c = context.pegasus;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAVORIS'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(favoriteAppsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: LayoutBuilder(builder: (context, box) {
            const cols = 4;
            const dots = 18.0;
            final tile = box.maxWidth / cols;
            final rows = ((box.maxHeight - dots) / tile).floor().clamp(1, 20);
            final perPage = cols * rows;
            final pages = apps.isEmpty ? 1 : (apps.length / perPage).ceil();
            final page = _page.clamp(0, pages - 1);
            return Column(
              children: [
                Expanded(
                  child: apps.isEmpty
                      ? const FavoritesGrid()
                      : PageView.builder(
                          itemCount: pages,
                          onPageChanged: (p) => setState(() => _page = p),
                          itemBuilder: (context, p) => Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              height: rows * tile,
                              child: FavoritesGrid(columns: cols, rows: rows, apps: apps.skip(p * perPage).take(perPage).toList()),
                            ),
                          ),
                        ),
                ),
                SizedBox(
                  height: dots,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages && pages > 1; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == page ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(color: i == page ? c.accent : c.line, borderRadius: BorderRadius.circular(3)),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
