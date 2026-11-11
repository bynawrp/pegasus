import 'package:flutter/material.dart';

import '../colors.dart';
import '../tokens.dart';

/// Carte de la DA : titre en capitales condensées, halo discret en sombre.
class PegasusPanel extends StatelessWidget {
  const PegasusPanel({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<PegasusColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PegasusRadii.card),
        border: Border.all(color: c.line),
        boxShadow: PegasusEffects.cardGlow(c.accent, theme.brightness),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 16, color: c.textMuted),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Pastille d'état colorée avec halo.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: PegasusEffects.neonGlow(color, Theme.of(context).brightness),
        ),
      );
}

/// Accès rapide aux couleurs Pegasus du thème courant.
extension PegasusThemeContext on BuildContext {
  PegasusColors get pegasus => Theme.of(this).extension<PegasusColors>()!;
}
