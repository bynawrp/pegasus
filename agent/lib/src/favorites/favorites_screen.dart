import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/agent_controller.dart';
import '../modules/apps/app_catalog.dart';

/// Favoris : applications proposées dans le module « Favoris » de l'app,
/// choisies parmi celles du menu Démarrer. Paginé (pas de défilement).
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  List<InstalledApp>? _apps;
  String _query = '';
  int _favPage = 0;
  int _appPage = 0;
  final _adding = <String>{};

  @override
  void initState() {
    super.initState();
    ref.read(agentControllerProvider.notifier).installedApps().then((apps) {
      if (mounted) setState(() => _apps = apps);
    }, onError: (_) {
      if (mounted) setState(() => _apps = const []);
    });
  }

  Future<void> _add(InstalledApp app) async {
    setState(() => _adding.add(app.id));
    await ref.read(agentControllerProvider.notifier).addFavorite(app);
    if (mounted) setState(() => _adding.remove(app.id));
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(agentControllerProvider).favorites;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('FAVORIS', style: text.headlineMedium),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _favoritesPanel(favorites)),
              const SizedBox(width: 16),
              Expanded(child: _catalogPanel(favorites)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _favoritesPanel(List<Favorite> favorites) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    return PegasusPanel(
      title: 'Proposés dans l’app (${favorites.length})',
      child: favorites.isEmpty
          ? Center(
              child: Text('Ajoutez des applications depuis la liste de droite.',
                  textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: c.textMuted)),
            )
          : _Paged(
              count: favorites.length,
              rowHeight: 52,
              page: _favPage,
              onPage: (p) => setState(() => _favPage = p),
              itemBuilder: (i) {
                final f = favorites[i];
                return Row(
                  key: ValueKey('fav-${f.id}'),
                  children: [
                    AppIcon(base64Png: f.icon, size: 32),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall)),
                    IconButton(
                      tooltip: 'Monter',
                      onPressed: i == 0 ? null : () => ref.read(agentControllerProvider.notifier).moveFavorite(f.id, -1),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Descendre',
                      onPressed: i == favorites.length - 1
                          ? null
                          : () => ref.read(agentControllerProvider.notifier).moveFavorite(f.id, 1),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    ),
                    IconButton(
                      key: ValueKey('remove-fav-${f.id}'),
                      tooltip: 'Retirer',
                      onPressed: () => ref.read(agentControllerProvider.notifier).removeFavorite(f.id),
                      icon: Icon(Icons.close_rounded, size: 18, color: c.danger),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _catalogPanel(List<Favorite> favorites) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final apps = _apps;
    final q = _query.trim().toLowerCase();
    final shown = apps == null ? const <InstalledApp>[] : [for (final a in apps) if (q.isEmpty || a.name.toLowerCase().contains(q)) a];
    final ids = {for (final f in favorites) f.id};

    return PegasusPanel(
      title: 'Ajouter une application',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: TextField(
              key: const ValueKey('app-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: 'Rechercher',
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _query = v;
                _appPage = 0;
              }),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: apps == null
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(child: Text('Aucune application trouvée', style: text.bodyMedium?.copyWith(color: c.textMuted)))
                    : _Paged(
                        count: shown.length,
                        rowHeight: 44,
                        page: _appPage,
                        onPage: (p) => setState(() => _appPage = p),
                        itemBuilder: (i) {
                          final a = shown[i];
                          final added = ids.contains(a.id);
                          final busy = _adding.contains(a.id);
                          return Row(
                            key: ValueKey('app-${a.id}'),
                            children: [
                              Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium)),
                              SizedBox(
                                width: 44,
                                child: busy
                                    ? const Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                    : IconButton(
                                        key: ValueKey('add-app-${a.id}'),
                                        tooltip: added ? 'Déjà en favori' : 'Ajouter',
                                        onPressed: added ? null : () => _add(a),
                                        icon: Icon(added ? Icons.check_rounded : Icons.add_rounded,
                                            color: added ? c.success : c.accent2),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Liste paginée : autant de lignes que la hauteur permet, flèches de page.
class _Paged extends StatelessWidget {
  const _Paged({
    required this.count,
    required this.rowHeight,
    required this.page,
    required this.onPage,
    required this.itemBuilder,
  });

  final int count;
  final double rowHeight;
  final int page;
  final ValueChanged<int> onPage;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const pager = 40.0;
      final perPage = ((box.maxHeight - pager) / rowHeight).floor().clamp(1, 1000);
      final pages = (count / perPage).ceil();
      final p = page.clamp(0, pages - 1);
      final start = p * perPage;
      final end = (start + perPage).clamp(0, count);
      return Column(
        children: [
          for (var i = start; i < end; i++) SizedBox(height: rowHeight, child: itemBuilder(i)),
          const Spacer(),
          SizedBox(
            height: pager,
            child: pages <= 1
                ? null
                : Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(onPressed: p > 0 ? () => onPage(p - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                      Text('${p + 1} / $pages', style: Theme.of(context).textTheme.labelLarge),
                      IconButton(onPressed: p < pages - 1 ? () => onPage(p + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                    ],
                  ),
          ),
        ],
      );
    });
  }
}

/// Icône d'application (PNG base64), ou icône générique.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.base64Png, this.size = 32});
  final String? base64Png;
  final double size;

  @override
  Widget build(BuildContext context) {
    final data = base64Png;
    if (data != null) {
      try {
        return Image.memory(base64.decode(data), width: size, height: size, gaplessPlayback: true);
      } catch (_) {}
    }
    return Icon(Icons.apps_rounded, size: size, color: context.pegasus.accent2);
  }
}
