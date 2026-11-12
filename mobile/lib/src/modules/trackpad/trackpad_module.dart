import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../../home/home_layout.dart';
import '../../home/home_layout_provider.dart';
import '../input/input_service.dart';
import '../module_gate.dart';
import '../registry.dart';
import 'trackpad_engine.dart';
import 'trackpad_settings.dart';

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
  late final HomePagingLock _lock;
  int _held = 0;

  @override
  void initState() {
    super.initState();
    _input = ref.read(inputServiceProvider);
    _lock = ref.read(homePagingLockProvider.notifier);
    _engine = TrackpadEngine(_ServiceSink(_input), settings: trackpadSettingsFor(ref.read(trackpadSpeedProvider)));
  }

  @override
  void dispose() {
    _engine.cancel();
    // Libère l'accueil si le widget disparaît doigt posé.
    for (; _held > 0; _held--) {
      _lock.release();
    }
    super.dispose();
  }

  void _hold() {
    _held++;
    _lock.hold();
  }

  void _release() {
    if (_held == 0) return;
    _held--;
    _lock.release();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    ref.listen(trackpadSpeedProvider, (_, speed) => _engine.settings = trackpadSettingsFor(speed));
    final surface = Listener(
      key: const ValueKey('trackpad-surface'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _hold();
        _engine.down(e.pointer, e.localPosition, e.timeStamp);
      },
      onPointerMove: (e) => _engine.move(e.pointer, e.localPosition, e.timeStamp),
      onPointerUp: (e) {
        _release();
        _engine.up(e.pointer, e.timeStamp);
      },
      onPointerCancel: (_) {
        _release();
        _engine.cancel();
      },
      child: RawGestureDetector(
        // Garde les gestes dans le trackpad (en plus du verrou des pages).
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
                      left: true,
                      onDown: () => _input.button(MouseButton.left, down: true),
                      onUp: () => _input.button(MouseButton.left, down: false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MouseButton(
                      key: const ValueKey('trackpad-right'),
                      left: false,
                      onDown: () => _input.button(MouseButton.right, down: true),
                      onUp: () => _input.button(MouseButton.right, down: false),
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
  const _MouseButton({super.key, required this.left, required this.onDown, required this.onUp});
  final bool left;
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
        child: Semantics(
          label: widget.left ? 'Clic gauche' : 'Clic droit',
          button: true,
          child: CustomPaint(
            size: const Size(20, 28),
            painter: MouseClickIcon(left: widget.left, outline: c.text, fill: _pressed ? c.accent : c.accent2),
          ),
        ),
      ),
    );
  }
}

/// Icône de souris avec le bouton gauche (ou droit) en surbrillance.
class MouseClickIcon extends CustomPainter {
  const MouseClickIcon({required this.left, required this.outline, required this.fill});
  final bool left;
  final Color outline;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width / 2));
    final split = size.height * 0.42;
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(Rect.fromLTWH(left ? 0 : size.width / 2, 0, size.width / 2, split), Paint()..color = fill);
    canvas.restore();
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(body, stroke);
    canvas.drawLine(Offset(0, split), Offset(size.width, split), stroke);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, split), stroke);
  }

  @override
  bool shouldRepaint(MouseClickIcon old) => old.left != left || old.outline != outline || old.fill != fill;
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

/// Écran plein du trackpad, avec le réglage de vitesse.
class TrackpadScreen extends ConsumerWidget {
  const TrackpadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(trackpadSpeedProvider);
    final text = Theme.of(context).textTheme;
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
                style: text.bodySmall,
              ),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Text('Vitesse', maxLines: 1, style: text.labelLarge),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('trackpad-speed'),
                        min: TrackpadSpeed.min,
                        max: TrackpadSpeed.max,
                        divisions: 8,
                        value: speed,
                        onChanged: (v) => ref.read(trackpadSpeedProvider.notifier).set(v),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('× ${speed.toStringAsFixed(2)}', maxLines: 1, style: text.labelMedium),
                    ),
                  ],
                ),
              ),
              const Expanded(child: TrackpadPad()),
            ],
          ),
        ),
      ),
    );
  }
}
