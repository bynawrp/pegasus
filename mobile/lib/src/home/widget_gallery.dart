import 'package:flutter/material.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../modules/registry.dart';
import 'home_layout.dart';

/// Galerie de widgets : choix du module puis de la taille.
Future<(String, WidgetSize)?> showWidgetGallery(BuildContext context) {
  final modules = moduleRegistry.where((m) => m.available && m.sizes.isNotEmpty).toList();
  return showModalBottomSheet<(String, WidgetSize)>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('AJOUTER UN WIDGET', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final m in modules) ...[
              Row(
                children: [
                  Icon(m.icon, color: context.pegasus.accent2),
                  const SizedBox(width: 10),
                  Text(m.name, style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 6),
              SizeChoices(
                keyPrefix: 'add-${m.id}',
                sizes: m.sizes,
                selected: m.defaultSize,
                onSelected: (s) => Navigator.pop(context, (m.id, s)),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    ),
  );
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
              style: s == selected
                  ? OutlinedButton.styleFrom(side: BorderSide(color: c.accent, width: 1.5))
                  : null,
              onPressed: () => onSelected(s),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${s.label} ${s.cols}×${s.rows}', maxLines: 1),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
