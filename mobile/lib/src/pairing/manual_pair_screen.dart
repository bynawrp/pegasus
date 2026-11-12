import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/pairing_service.dart';
import 'pin_code_field.dart';

/// Adresse saisie : IPv4 (virgules acceptées comme points) avec port
/// optionnel collé (`192.168.1.20:47800`).
({String host, int? port})? parseHostInput(String raw) {
  final value = raw.trim().replaceAll(',', '.');
  final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{1,5}))?$').firstMatch(value);
  if (m == null) return null;
  if (m.group(1)!.split('.').any((p) => int.parse(p) > 255)) return null;
  final port = m.group(2) == null ? null : int.parse(m.group(2)!);
  if (port != null && (port < 1 || port > 65535)) return null;
  return (host: m.group(1)!, port: port);
}

/// Formatage de l'adresse pendant la saisie : chiffres, points (la virgule
/// du pavé décimal devient un point) et `:` pour un port collé.
class HostInputFormatter extends TextInputFormatter {
  const HostInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.:]'), '');
    if (text == newValue.text) return newValue;
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}

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
  final _codeFocus = FocusNode();
  bool _busy = false;
  String? _error;

  /// Empreinte reçue, en attente de confirmation par l'utilisateur.
  String? _fingerprint;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Adresse et port validés, ou `null` avec un message d'erreur.
  ({String host, int port})? _target() {
    final parsed = parseHostInput(_host.text);
    if (parsed == null) {
      setState(() => _error = 'Adresse invalide (ex. 192.168.1.20).');
      return null;
    }
    final port = parsed.port ?? int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Port invalide.');
      return null;
    }
    // Port collé avec l'adresse : on l'affiche dans son champ.
    if (parsed.port != null) {
      _host.text = parsed.host;
      _port.text = '${parsed.port}';
    }
    return (host: parsed.host, port: port);
  }

  Future<void> _continue() async {
    if (_busy) return;
    final target = _target();
    if (target == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _error = 'Saisissez le code à 6 chiffres.');
      _codeFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    await _run(() async {
      final fp = await ref.read(pairingServiceProvider).probe(target.host, target.port);
      setState(() => _fingerprint = fp);
    });
  }

  Future<void> _confirm() async {
    final fp = _fingerprint!;
    final target = _target();
    if (target == null) return;
    await _run(() async {
      await ref.read(pairingServiceProvider).pairWithCode(
            host: target.host,
            port: target.port,
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
    return LayoutBuilder(builder: (context, box) {
      // Clavier ouvert sur un petit écran : explication et bouton masqués,
      // le code se valide tout seul au 6e chiffre.
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
                  // iOS : pavé chiffres + ponctuation (avec le point).
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  inputFormatters: const [HostInputFormatter()],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  onSubmitted: (_) => _codeFocus.requestFocus(),
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
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
            ],
          ),
          SizedBox(height: roomy ? 16 : 10),
          if (roomy) ...[
            Text('CODE À 6 CHIFFRES', style: text.labelSmall),
            const SizedBox(height: 6),
          ],
          PinCodeField(
            controller: _code,
            focusNode: _codeFocus,
            enabled: !_busy,
            onCompleted: (_) => _continue(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                key: const ValueKey('pair-error'),
                maxLines: roomy ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: c.danger)),
          ],
          if (_busy && !roomy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (roomy) ...[
            const Spacer(),
            FilledButton(
              key: const ValueKey('continue'),
              onPressed: _busy ? null : _continue,
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Continuer'),
            ),
          ],
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
              : const Text('C’est la même : associer', maxLines: 1),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const ValueKey('reject-fingerprint'),
          onPressed: _busy ? null : () => setState(() => _fingerprint = null),
          child: const Text('Différente : annuler', maxLines: 1),
        ),
      ],
    );
  }
}
