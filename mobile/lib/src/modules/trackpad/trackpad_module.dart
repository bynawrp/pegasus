import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../../home/home_layout.dart';
import '../input/input_service.dart';
import '../module_gate.dart';
import '../registry.dart';
import 'trackpad_engine.dart';

final trackpadModule = PegasusModule(
  id: 'trackpad',
  name: 'Trackpad',
  icon: Icons.touch_app_rounded,
  category: ModuleCategory.control,
  tier: ModuleTier.mvp,
  permission: 'input',
  sizes: const [WidgetSize.medium, WidgetSize.wide, WidgetSize.large],
  defaultSize: WidgetSize.large,
  screen: (_) => const TrackpadScreen(),
  widget: (context, size) => TrackpadPad(showButtons: size == WidgetSize.large, compact: size != WidgetSize.large),
);

/// Relie le moteur de gestes au service d'entrée (+ retour haptique).
class _ServiceSink implements TrackpadSink {
  _ServiceSink(this.service);
  final InputService service;

  @override
  void move(double dx, double dy) => service.move(dx, dy);

  @override
  void scroll(double dx, double dy) => service.scroll(dx, dy);

  @override
  void click(MouseButton button) {
    HapticFeedback.selectionClick();
    service.click(button);
  }

  @override
  void button(MouseButton button, {required bool down}) {
    if (down) HapticFeedback.lightImpact();
    service.button(button, down: down);
  }
}

/// Surface tactile + boutons (widget d'accueil et écran plein).
class TrackpadPad extends ConsumerStatefulWidget {
  const TrackpadPad({super.key, this.showButtons = true, this.compact = false});

  final bool showButtons;
  final bool compact;

  @override
  ConsumerState<TrackpadPad> createState() => _TrackpadPadState();
}

class _TrackpadPadState extends ConsumerState<TrackpadPad> {
  late final TrackpadEngine _engine;
  late final InputService _input;

  @override
  void initState() {
    super.initState();
    _input = ref.read(inputServiceProvider);
    _engine = TrackpadEngine(_ServiceSink(_input));
  }

  @override
  void dispose() {
    _engine.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final input = _input;
    final surface = Listener(
      key: const ValueKey('trackpad-surface'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _engine.down(e.pointer, e.localPosition, e.timeStamp),
      onPointerMove: (e) => _engine.move(e.pointer, e.localPosition, e.timeStamp),
      onPointerUp: (e) => _engine.up(e.pointer, e.timeStamp),
      onPointerCancel: (_) => _engine.cancel(),
      child: RawGestureDetector(
        // Empêche le défilement des pages de l'accueil de voler les gestes.
        gestures: {
          _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(_EagerPan.new, (_) {}),
        },
        child: Container(
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            borderRadius: BorderRadius.circular(PegasusRadii.control),
            border: Border.all(color: c.line),
          ),
          child: Center(
            child: Icon(Icons.touch_app_outlined, size: widget.compact ? 22 : 32, color: c.textMuted.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );

    return ModuleGate(
      permission: 'input',
      compact: widget.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: surface),
          if (widget.showButtons) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: PegasusSizes.minTouch,
              child: Row(
                children: [
                  Expanded(
                    child: _MouseButton(
                      key: const ValueKey('trackpad-left'),
                      label: 'Gauche',
                      onDown: () => input.button(MouseButton.left, down: true),
                      onUp: () => input.button(MouseButton.left, down: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MouseButton(
                      key: const ValueKey('trackpad-right'),
                      label: 'Droit',
                      onDown: () => input.button(MouseButton.right, down: true),
                      onUp: () => input.button(MouseButton.right, down: false),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bouton physique : appui = bouton enfoncé (permet le glisser-déposer).
class _MouseButton extends StatefulWidget {
  const _MouseButton({super.key, required this.label, required this.onDown, required this.onUp});
  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_MouseButton> createState() => _MouseButtonState();
}

class _MouseButtonState extends State<_MouseButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    if (v) {
      HapticFeedback.selectionClick();
      widget.onDown();
    } else {
      widget.onUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _pressed ? c.accent.withValues(alpha: 0.25) : c.surfaceHigh,
          borderRadius: BorderRadius.circular(PegasusRadii.control),
          border: Border.all(color: _pressed ? c.accent : c.line),
        ),
        child: Text(widget.label, maxLines: 1, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}

/// Reconnaît tout de suite un glissement pour garder les gestes dans le trackpad.
class _EagerPan extends PanGestureRecognizer {
  _EagerPan() : super();

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Écran plein du trackpad.
class TrackpadScreen extends StatelessWidget {
  const TrackpadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TRACKPAD')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tap : clic · 2 doigts : clic droit / défiler · tap puis glisser : déplacer',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              const Expanded(child: TrackpadPad()),
            ],
          ),
        ),
      ),
    );
  }
}
