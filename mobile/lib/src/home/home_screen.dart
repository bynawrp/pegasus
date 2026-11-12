import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../app/shell.dart';
import '../core/providers.dart';

/// Accueil. La grille de widgets 4×6 arrive avec les premiers modules ;
/// pour l'instant : état de la connexion.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final link = ref.watch(linkStateProvider);
    final pc = ref.watch(pairedPcProvider).value;
    final color = linkColor(context, link);
    return PegasusPanel(
      title: 'Accueil',
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.computer_rounded, size: 64, color: color),
                const SizedBox(height: 12),
                Text(pc?.agentName ?? '', textAlign: TextAlign.center, maxLines: 2, style: text.headlineSmall),
                const SizedBox(height: 6),
                Text(linkLabel(link), style: text.bodyMedium?.copyWith(color: color)),
                const SizedBox(height: 20),
                Text(
                  'Vos modules (trackpad, clavier, médias…) apparaîtront ici.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
