import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../../home/home_layout.dart';
import '../action_feedback.dart';
import '../input/input_service.dart';
import '../module_gate.dart';
import '../registry.dart';

final linkModule = PegasusModule(
  id: 'link',
  name: 'Ouvrir un lien',
  icon: Icons.link_rounded,
  category: ModuleCategory.apps,
  tier: ModuleTier.mvp,
  permission: 'apps',
  sizes: const [WidgetSize.small],
  defaultSize: WidgetSize.small,
  screen: (_) => const LinkScreen(),
);

/// Envoi d'un lien vers le navigateur du PC (champ, collage, partage).
class LinkScreen extends ConsumerStatefulWidget {
  const LinkScreen({super.key, this.initialUrl});

  /// Lien reçu par le menu Partager / un raccourci iOS.
  final String? initialUrl;

  @override
  ConsumerState<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends ConsumerState<LinkScreen> {
  late final _controller = TextEditingController(text: widget.initialUrl ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    final url = extractUrl(text) ?? text.trim();
    if (url.isEmpty) return;
    setState(() {
      _controller.text = url;
      _error = null;
    });
  }

  Future<void> _send() async {
    final raw = _controller.text.trim();
    final url = extractUrl(raw) ?? (raw.contains('://') ? raw : 'https://$raw');
    try {
      parseUrl({'url': url});
    } on InputValidationError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await runAction(
      context,
      () => ref.read(remoteSenderProvider).request('url.open', {'url': url}),
      success: 'Lien ouvert sur le PC',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && widget.initialUrl != null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('OUVRIR UN LIEN')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ModuleGate(
            permission: 'apps',
            child: LayoutBuilder(builder: (context, box) {
              final roomy = box.maxHeight > 260;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (roomy) ...[
                    Text('Le lien s’ouvre dans le navigateur du PC.',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: c.textMuted)),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const ValueKey('link-url'),
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      labelText: 'Lien (https://…)',
                      errorText: _error,
                      errorMaxLines: 2,
                      suffixIcon: IconButton(
                        key: const ValueKey('link-paste'),
                        tooltip: 'Coller',
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('link-send'),
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text('Ouvrir sur le PC', maxLines: 1),
                  ),
                  if (roomy) ...[
                    const Spacer(),
                    if (Platform.isIOS)
                      TextButton.icon(
                        key: const ValueKey('link-ios-help'),
                        onPressed: () => _showIosShortcutHelp(context),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Partager depuis Safari ou une app', maxLines: 1),
                      )
                    else
                      Text(
                        'Astuce : depuis n’importe quelle app, Partager → Pegasus.',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: text.bodySmall,
                      ),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Marche à suivre pour le raccourci iOS « Ouvrir sur le PC » (feuille de partage).
Future<void> _showIosShortcutHelp(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        const steps = [
          'Ouvrez l’app Raccourcis → « + » (nouveau raccourci).',
          'Réglages du raccourci (ⓘ) : activez « Afficher dans la feuille de partage », type URL.',
          'Ajoutez l’action « Encoder en URL » sur l’« Entrée du raccourci ».',
          'Ajoutez « Ouvrir les URL » avec : pegasus://open?url= suivi du résultat encodé.',
          'Nommez-le « Ouvrir sur le PC ». Il apparaît ensuite dans Partager.',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('PARTAGER VERS LE PC (iOS)', style: text.titleLarge),
                const SizedBox(height: 10),
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${i + 1}. ${steps[i]}', style: text.bodyMedium),
                  ),
              ],
            ),
          ),
        );
      },
    );
