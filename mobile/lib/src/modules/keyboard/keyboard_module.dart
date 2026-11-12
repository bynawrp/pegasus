import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../../home/home_layout.dart';
import '../input/input_service.dart';
import '../module_gate.dart';
import '../registry.dart';
import 'keyboard_diff.dart';

final keyboardModule = PegasusModule(
  id: 'keyboard',
  name: 'Clavier',
  icon: Icons.keyboard_rounded,
  category: ModuleCategory.control,
  tier: ModuleTier.mvp,
  permission: 'input',
  sizes: const [WidgetSize.small, WidgetSize.wide],
  defaultSize: WidgetSize.wide,
  screen: (_) => const KeyboardScreen(),
  widget: (context, size) => size == WidgetSize.small ? const SizedBox.shrink() : const KeyboardShortcutsPad(),
);

/// Une touche spéciale ou un raccourci.
class KeySpec {
  const KeySpec(this.label, this.key, [this.modifiers = const []]);
  final String label;
  final String key;
  final List<KeyModifier> modifiers;
}

const specialKeys = [
  KeySpec('Échap', 'escape'),
  KeySpec('Tab', 'tab'),
  KeySpec('←', 'left'),
  KeySpec('↑', 'up'),
  KeySpec('↓', 'down'),
  KeySpec('→', 'right'),
  KeySpec('Suppr', 'delete'),
  KeySpec('⏎', 'enter'),
];

const shortcutKeys = [
  KeySpec('Alt+Tab', 'tab', [KeyModifier.alt]),
  KeySpec('Copier', 'c', [KeyModifier.ctrl]),
  KeySpec('Coller', 'v', [KeyModifier.ctrl]),
  KeySpec('Annuler', 'z', [KeyModifier.ctrl]),
  KeySpec('Tout', 'a', [KeyModifier.ctrl]),
  KeySpec('Bureau', 'd', [KeyModifier.win]),
  KeySpec('Win', 'win'),
  KeySpec('Fermer', 'f4', [KeyModifier.alt]),
];

/// Rangée de touches, toutes de même largeur (pas de défilement).
class KeyRow extends ConsumerWidget {
  const KeyRow({super.key, required this.keys, this.extraModifiers = const [], this.onSent, this.height = 40});

  final List<KeySpec> keys;
  final List<KeyModifier> extraModifiers;
  final VoidCallback? onSent;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final input = ref.read(inputServiceProvider);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Material(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(PegasusRadii.control),
                child: InkWell(
                  key: ValueKey('key-${keys[i].label}'),
                  borderRadius: BorderRadius.circular(PegasusRadii.control),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    input.key(keys[i].key, modifiers: {...keys[i].modifiers, ...extraModifiers}.toList());
                    onSent?.call();
                  },
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(keys[i].label, maxLines: 1, style: Theme.of(context).textTheme.labelLarge),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Widget d'accueil 4×2 : touches spéciales + raccourcis.
class KeyboardShortcutsPad extends StatelessWidget {
  const KeyboardShortcutsPad({super.key});

  @override
  Widget build(BuildContext context) {
    return ModuleGate(
      permission: 'input',
      compact: true,
      child: LayoutBuilder(builder: (context, box) {
        final h = ((box.maxHeight - 4) / 2).clamp(0.0, 44.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            KeyRow(keys: specialKeys.sublist(0, 4) + specialKeys.sublist(6), height: h),
            const SizedBox(height: 4),
            KeyRow(keys: shortcutKeys.sublist(0, 4), height: h),
          ],
        );
      }),
    );
  }
}

/// Écran plein : frappe en direct (corrections incluses), modificateurs,
/// touches spéciales et raccourcis.
class KeyboardScreen extends ConsumerStatefulWidget {
  const KeyboardScreen({super.key});

  @override
  ConsumerState<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends ConsumerState<KeyboardScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _sent = '';
  final _modifiers = <KeyModifier>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  InputService get _input => ref.read(inputServiceProvider);

  void _onChanged() {
    final value = _controller.value;
    // Pendant la composition (accents, IME), on attend le texte final.
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final text = value.text;
    if (text == _sent) return;

    // Modificateur actif + une lettre : raccourci (ex. Ctrl+S) au lieu du texte.
    if (_modifiers.isNotEmpty && text.length == _sent.length + 1 && text.startsWith(_sent)) {
      final ch = text.substring(_sent.length).toLowerCase();
      if (InputKeys.isValid(ch)) {
        _input.key(ch, modifiers: _modifiers.toList());
        setState(_modifiers.clear);
        _reset(_sent);
        return;
      }
    }
    for (final action in diffText(_sent, text)) {
      switch (action) {
        case TypeText(:final text):
          _input.text(text);
        case PressKey(:final key, :final repeat):
          _input.key(key, repeat: repeat);
      }
    }
    _sent = text;
    // Le tampon ne grossit pas indéfiniment.
    if (_sent.length > 300) _reset('');
  }

  /// Remplace le texte du champ sans rien envoyer.
  void _reset(String text) {
    _sent = text;
    _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _submit() {
    _input.key('enter');
    _reset('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('CLAVIER')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ModuleGate(
            permission: 'input',
            child: LayoutBuilder(builder: (context, box) {
              // Clavier système ouvert sur petit écran : on garde l'essentiel.
              final roomy = box.maxHeight >= 250;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('keyboard-input'),
                    controller: _controller,
                    focusNode: _focus,
                    autocorrect: true,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Tapez, le texte part en direct',
                      isDense: !roomy,
                      suffixIcon: IconButton(
                        tooltip: 'Entrée',
                        onPressed: _submit,
                        icon: const Icon(Icons.keyboard_return_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: Row(
                      children: [
                        for (final m in KeyModifier.values) ...[
                          if (m != KeyModifier.values.first) const SizedBox(width: 4),
                          Expanded(
                            child: FilterChip(
                              key: ValueKey('mod-${m.name}'),
                              label: SizedBox(
                                width: double.infinity,
                                child: Text(_modLabel(m), maxLines: 1, textAlign: TextAlign.center),
                              ),
                              showCheckmark: false,
                              selected: _modifiers.contains(m),
                              selectedColor: c.accent.withValues(alpha: 0.3),
                              padding: EdgeInsets.zero,
                              labelPadding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onSelected: (v) => setState(() => v ? _modifiers.add(m) : _modifiers.remove(m)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  KeyRow(
                    keys: specialKeys,
                    extraModifiers: _modifiers.toList(),
                    onSent: () => setState(_modifiers.clear),
                  ),
                  if (roomy) ...[
                    const SizedBox(height: 6),
                    KeyRow(keys: shortcutKeys),
                    const Spacer(),
                    Text(
                      'Ctrl, Alt, Maj ou Win puis une lettre : envoie le raccourci (ex. Ctrl + S).',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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

  static String _modLabel(KeyModifier m) => switch (m) {
        KeyModifier.ctrl => 'Ctrl',
        KeyModifier.alt => 'Alt',
        KeyModifier.shift => 'Maj',
        KeyModifier.win => 'Win',
      };
}
