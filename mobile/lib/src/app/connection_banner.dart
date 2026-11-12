import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/providers.dart';
import '../pairing/onboarding_screen.dart';
import 'shell.dart';

/// Bandeau d'état de la connexion, en haut de l'app (hauteur fixe).
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key, required this.state, required this.pcName});

  final LinkState state;
  final String pcName;

  static const height = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final color = linkColor(context, state);

    Widget? action;
    if (state.needsUserAction) {
      action = TextButton(
        key: const ValueKey('repair'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const OnboardingScreen(canGoBack: true)),
        ),
        child: const Text('Réassocier'),
      );
    } else if (state.status == LinkStatus.waiting || state.status == LinkStatus.replaced) {
      action = TextButton(
        key: const ValueKey('retry'),
        onPressed: () => ref.read(linkStateProvider.notifier).reconnect(),
        child: const Text('Réessayer'),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          const PegasusLogo(size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pcName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Row(
                  children: [
                    StatusDot(color: color, size: 7),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        linkLabel(state),
                        key: const ValueKey('link-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
