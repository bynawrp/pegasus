import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../app/shell.dart';
import '../core/providers.dart';
import '../pairing/onboarding_screen.dart';

/// Mes PC : PC associé, état, reconnexion, oubli.
class MyPcScreen extends ConsumerWidget {
  const MyPcScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pc = ref.watch(pairedPcProvider).value;
    final link = ref.watch(linkStateProvider);
    if (pc == null) return const SizedBox.shrink();
    final info = link.info;
    final rows = <(String, String, bool)>[
      ('État', linkLabel(link), false),
      ('Adresse', '${pc.host}:${pc.port}', true),
      ('Empreinte', PegasusCrypto.shortFingerprint(pc.fingerprint), true),
      if (info != null) ('Agent', 'v${info.agentVersion} · ${info.os}', false),
    ];
    final text = Theme.of(context).textTheme;
    final c = context.pegasus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PegasusPanel(
            title: 'Mes PC',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.computer_rounded, color: linkColor(context, link), size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(pc.agentName,
                          key: const ValueKey('pc-name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.headlineSmall),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final (label, value, mono) in rows)
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: [
                        SizedBox(width: 90, child: Text(label, style: text.bodySmall)),
                        Expanded(
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono
                                ? TextStyle(
                                    fontFamily: PegasusFonts.mono,
                                    package: PegasusFonts.package,
                                    fontSize: 13,
                                    color: c.text)
                                : text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('reconnect'),
                onPressed: link.isConnected || link.status == LinkStatus.connecting
                    ? null
                    : () => ref.read(linkStateProvider.notifier).reconnect(),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Reconnecter', maxLines: 1)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('forget'),
                style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                onPressed: () => _forget(context, ref, pc.agentName),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Oublier ce PC', maxLines: 1)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('pair-other'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const OnboardingScreen(canGoBack: true)),
          ),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Associer un autre PC', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OUBLIER CE PC ?'),
        content: Text('« $name » retirera aussi ce téléphone de sa liste. Il faudra l’associer à nouveau.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            key: const ValueKey('confirm-forget'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oublier'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(linkStateProvider.notifier).forgetPc();
  }
}
