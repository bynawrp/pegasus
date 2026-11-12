import 'package:flutter/material.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import 'registry.dart';

/// Catalogue des modules : grille paginée (pas de défilement continu).
class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  final _pages = PageController();
  int _page = 0;

  static const _cols = 3;
  static const _tileHeight = 84.0;
  static const _gap = 8.0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    // Disponibles d'abord, puis par catégorie.
    final modules = [...moduleRegistry]
      ..sort((a, b) => a.available == b.available ? a.category.index - b.category.index : (a.available ? -1 : 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('MODULES', style: text.headlineSmall),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, outer) {
            const dotsHeight = 18.0;
            final height = outer.maxHeight - dotsHeight;
            final rows = ((height + _gap) / (_tileHeight + _gap)).floor().clamp(1, 100);
            final perPage = rows * _cols;
            final pageCount = (modules.length / perPage).ceil();
            final tileW = (outer.maxWidth - _gap * (_cols - 1)) / _cols;
            final tileH = ((height + _gap) / rows - _gap).clamp(0.0, _tileHeight + 20);
            final page = _page.clamp(0, pageCount - 1);
            return Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    key: const ValueKey('modules-pages'),
                    controller: _pages,
                    itemCount: pageCount,
                    onPageChanged: (p) => setState(() => _page = p),
                    itemBuilder: (context, p) {
                      final slice = modules.skip(p * perPage).take(perPage).toList();
                      return Wrap(
                        spacing: _gap,
                        runSpacing: _gap,
                        children: [
                          for (final m in slice) SizedBox(width: tileW, height: tileH, child: _ModuleTile(module: m)),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: dotsHeight,
                  child: Row(
                    key: const ValueKey('modules-dots'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pageCount; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == page ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == page ? c.accent : c.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});
  final PegasusModule module;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final available = module.available;
    final tier = switch (module.tier) {
      ModuleTier.mvp => 'Bientôt',
      ModuleTier.v2 => 'V2',
      ModuleTier.v3 => 'V3',
    };
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(PegasusRadii.card),
      child: InkWell(
        key: ValueKey('module-${module.id}'),
        borderRadius: BorderRadius.circular(PegasusRadii.card),
        onTap: available
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: module.screen!))
            : () => ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text('${module.name} arrive dans une prochaine version.'))),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PegasusRadii.card),
            border: Border.all(color: available ? c.accent2.withValues(alpha: 0.5) : c.line),
          ),
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(module.icon, size: 26, color: available ? c.accent2 : c.textMuted.withValues(alpha: 0.6)),
                const SizedBox(height: 4),
                Text(module.name, maxLines: 1, style: text.labelLarge?.copyWith(color: available ? c.text : c.textMuted)),
                if (!available) Text(tier, maxLines: 1, style: text.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
