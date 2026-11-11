import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/pairing_service.dart';
import 'manual_pair_screen.dart';

typedef QrScannerBuilder = Widget Function(BuildContext context, void Function(String code) onCode);

/// Vue caméra (remplacée par un faux scanner dans les tests).
final qrScannerProvider = Provider<QrScannerBuilder>((ref) => (context, onCode) => MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
        if (value != null) onCode(value);
      },
      errorBuilder: (context, error) => _CameraError(error: error),
    ));

/// Scan du QR code affiché par l'agent, puis appairage.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _busy = false;
  String? _error;
  String? _lastCode;

  Future<void> _onCode(String code) async {
    if (_busy || code == _lastCode) return;
    setState(() {
      _busy = true;
      _error = null;
      _lastCode = code;
    });
    try {
      await ref.read(pairingServiceProvider).pairWithQr(code);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on PairingFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SCANNER LE QR CODE')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(PegasusRadii.card),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ref.watch(qrScannerProvider)(context, _onCode),
                      IgnorePointer(
                        child: Center(
                          child: FractionallySizedBox(
                            widthFactor: 0.7,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: c.accent2, width: 3),
                                  borderRadius: BorderRadius.circular(PegasusRadii.card),
                                  boxShadow: PegasusEffects.neonGlow(c.accent2, Theme.of(context).brightness),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_busy)
                        ColoredBox(
                          color: c.background.withValues(alpha: 0.7),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _error ?? 'Visez le QR code affiché dans Pegasus sur votre PC.',
                    key: const ValueKey('scan-message'),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: _error == null ? c.textMuted : c.danger),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(builder: (_) => const ManualPairScreen()),
                    ),
                    child: const Text('Saisir le code à la main'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: context.pegasus.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            denied
                ? 'Accès à la caméra refusé. Autorisez-le dans les réglages du téléphone, ou saisissez le code à la main.'
                : 'Caméra indisponible. Saisissez le code à la main.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
