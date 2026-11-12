import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/local_network.dart';
import '../core/providers.dart';
import 'manual_pair_screen.dart';
import 'scan_screen.dart';

/// Premier lancement (ou PC oublié) : associer un PC.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key, this.canGoBack = false});

  /// Vrai quand on vient de « Mes PC » (remplacer le PC associé).
  final bool canGoBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final notice = ref.watch(pairingNoticeProvider);
    final network = ref.watch(localNetworkProvider);
    final allowed = network == LocalNetworkAccess.granted;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: canGoBack ? AppBar(backgroundColor: Colors.transparent) : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notice != null)
                Container(
                  key: const ValueKey('pairing-notice'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(PegasusRadii.control),
                    border: Border.all(color: c.danger.withValues(alpha: 0.5)),
                  ),
                  child: Text(notice, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              if (network == LocalNetworkAccess.denied)
                Container(
                  key: const ValueKey('network-denied'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: c.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(PegasusRadii.control),
                    border: Border.all(color: c.warning.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pegasus a besoin de l’accès au réseau local pour joindre votre PC.',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: c.text),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('open-settings'),
                        onPressed: () => ref.read(localNetworkProvider.notifier).openSettings(),
                        child: const Text('Réglages', maxLines: 1),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const PegasusLogo(size: 104),
                          const SizedBox(height: 16),
                          Text('PEGASUS', style: text.displaySmall?.copyWith(letterSpacing: 4)),
                          const SizedBox(height: 8),
                          Text('Contrôlez votre PC depuis votre téléphone.',
                              textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(color: c.textMuted)),
                          const SizedBox(height: 28),
                          const _Step(n: 1, text: 'Lancez Pegasus sur votre PC.'),
                          const _Step(n: 2, text: 'Connectez le téléphone au même Wi-Fi.'),
                          const _Step(n: 3, text: 'Scannez le QR code affiché sur le PC.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('scan-qr'),
                onPressed: !allowed ? null : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(
                  network == LocalNetworkAccess.checking ? 'Autorisation réseau en attente…' : 'Scanner le QR code',
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('manual-pair'),
                onPressed: !allowed ? null : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ManualPairScreen()),
                ),
                child: const Text('Saisir le code à la main'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.accent2),
            ),
            child: Text('$n', style: TextStyle(color: c.accent2, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
