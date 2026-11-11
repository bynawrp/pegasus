import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/pairing_service.dart';

/// Appairage par code manuel (spec §3) : adresse + code, puis vérification
/// de l'empreinte du certificat affichée par le PC.
class ManualPairScreen extends ConsumerStatefulWidget {
  const ManualPairScreen({super.key});

  @override
  ConsumerState<ManualPairScreen> createState() => _ManualPairScreenState();
}

class _ManualPairScreenState extends ConsumerState<ManualPairScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '$defaultPort');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Empreinte reçue, en attente de confirmation par l'utilisateur.
  String? _fingerprint;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  int? get _portValue {
    final p = int.tryParse(_port.text.trim());
    return p != null && p > 0 && p < 65536 ? p : null;
  }

  Future<void> _continue() async {
    final port = _portValue;
    final code = _code.text.replaceAll(' ', '');
    if (_host.text.trim().isEmpty || port == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Adresse, port et code à 6 chiffres requis.');
      return;
    }
    FocusScope.of(context).unfocus();
    await _run(() async {
      final fp = await ref.read(pairingServiceProvider).probe(_host.text, port);
      setState(() => _fingerprint = fp);
    });
  }

  Future<void> _confirm() async {
    final fp = _fingerprint!;
    await _run(() async {
      await ref.read(pairingServiceProvider).pairWithCode(
            host: _host.text,
            port: _portValue!,
            fingerprint: fp,
            code: _code.text,
          );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on PairingFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CODE MANUEL')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _fingerprint == null ? _form(context) : _verify(context),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final codeField = TextField(
      key: const ValueKey('code'),
      controller: _code,
      enabled: !_busy,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      style: const TextStyle(fontFamily: PegasusFonts.mono, package: PegasusFonts.package, letterSpacing: 4),
      decoration: const InputDecoration(labelText: 'Code à 6 chiffres'),
      onSubmitted: (_) => _continue(),
    );
    final continueButton = FilledButton(
      key: const ValueKey('continue'),
      onPressed: _busy ? null : _continue,
      child: _busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Continuer'),
    );
    return LayoutBuilder(builder: (context, box) {
      // Clavier ouvert sur un petit écran : on masque l'explication et on
      // remonte le bouton à côté du code.
      final roomy = box.maxHeight > 300;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (roomy) ...[
            Text(
              'Sur le PC, la carte « Associer un téléphone » affiche l’adresse et le code.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('host'),
                  controller: _host,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Adresse du PC', hintText: '192.168.1.20'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('port'),
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (roomy) codeField else
            // Clavier ouvert sur petit écran : code et bouton sur une ligne.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: codeField),
                const SizedBox(width: 10),
                SizedBox(height: 56, child: continueButton),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                key: const ValueKey('pair-error'),
                maxLines: roomy ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: c.danger)),
          ],
          if (roomy) ...[const Spacer(), continueButton],
        ],
      );
    });
  }

  Widget _verify(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final short = PegasusCrypto.shortFingerprint(_fingerprint!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 48, color: c.accent2),
                    const SizedBox(height: 16),
                    Text('VÉRIFIEZ L’EMPREINTE', style: text.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Le PC doit afficher exactement la même empreinte. Sinon, annulez.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: c.textMuted),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      short,
                      key: const ValueKey('fingerprint'),
                      style: TextStyle(
                        fontFamily: PegasusFonts.mono,
                        package: PegasusFonts.package,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                        color: c.accent2,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          key: const ValueKey('pair-error'),
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: c.danger)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        FilledButton(
          key: const ValueKey('confirm-fingerprint'),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('C’est la même : associer'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const ValueKey('reject-fingerprint'),
          onPressed: _busy ? null : () => setState(() => _fingerprint = null),
          child: const Text('Différente : annuler'),
        ),
      ],
    );
  }
}
