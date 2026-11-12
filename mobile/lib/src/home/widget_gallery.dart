import 'package:flutter/material.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../modules/registry.dart';
import 'home_layout.dart';

/// Galerie de widgets en deux étapes : module (grille), puis taille.
/// Hauteur bornée quel que soit le nombre de modules (grille paginée).
Future<(String, WidgetSize)?> showWidgetGallery(BuildContext context) {
  final modules = moduleRegistry.where((m) => m.available && m.sizes.isNotEmpty).toList();
  return showModalBottomSheet<(String, WidgetSize)>(
    context: context,
    builder: (context) => SafeArea(child: _Gallery(modules: modules)),
  );
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.modules});
  final List<PegasusModule> modules;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  PegasusModule? _picked;
  int _page = 0;

  static const _cols = 3;
  static const _rows = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final picked = _picked;
    final perPage = _cols * _rows;
    final pages = (widget.modules.length / perPage).ceil();
    final page = _page.clamp(0, pages - 1);
    final slice = widget.modules.skip(page * perPage).take(perPage).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                if (picked != null)
                  IconButton(
                    key: const ValueKey('gallery-back'),
                    tooltip: 'Retour',
                    onPressed: () => setState(() => _picked = null),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Text(
                    picked == null ? 'AJOUTER UN WIDGET' : picked.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge,
                  ),
                ),
                if (picked == null && pages > 1) ...[
                  IconButton(
                    onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('gallery-next'),
                    onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 2 * 76 + 8,
            child: picked == null
                ? GridView.count(
                    crossAxisCount: _cols,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.6,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final m in slice)
                        Material(
                          color: c.surfaceHigh,
                          borderRadius: BorderRadius.circular(PegasusRadii.control),
                          child: InkWell(
                            key: ValueKey('gallery-${m.id}'),
                            borderRadius: BorderRadius.circular(PegasusRadii.control),
                            onTap: () => setState(() => _picked = m),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(m.icon, color: c.accent2, size: 26),
                                    const SizedBox(height: 4),
                                    Text(m.name, maxLines: 1, style: text.labelMedium),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: SizeChoices(
                      keyPrefix: 'add-${picked.id}',
                      sizes: picked.sizes,
                      selected: picked.defaultSize,
                      onSelected: (s) => Navigator.pop(context, (picked.id, s)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Boutons de taille (Petit · Moyen · Large · Grand), sur une ligne.
class SizeChoices extends StatelessWidget {
  const SizeChoices({
    super.key,
    required this.sizes,
    required this.onSelected,
    this.selected,
    this.keyPrefix = 'size',
  });

  final List<WidgetSize> sizes;
  final WidgetSize? selected;
  final ValueChanged<WidgetSize> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    return Row(
      children: [
        for (final s in sizes) ...[
          if (s != sizes.first) const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              key: ValueKey('$keyPrefix-${s.name}'),
              style: s == selected ? OutlinedButton.styleFrom(side: BorderSide(color: c.accent, width: 1.5)) : null,
              onPressed: () => onSelected(s),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text('${s.label} ${s.cols}×${s.rows}', maxLines: 1)),
            ),
          ),
        ],
      ],
    );
  }
}
