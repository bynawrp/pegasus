import 'dart:math';
import 'dart:ui';

import 'package:pegasus_protocol/pegasus_protocol.dart';

/// Sortie du trackpad (implémentée par [InputService] ou un enregistreur).
abstract class TrackpadSink {
  void move(double dx, double dy);
  void scroll(double dx, double dy);
  void click(MouseButton button);
  void button(MouseButton button, {required bool down});
}

/// Réglages des gestes.
class TrackpadSettings {
  const TrackpadSettings({
    this.sensitivity = 2.2,
    this.acceleration = 1.5,
    this.pixelsPerNotch = 24,
    this.tapMaxDuration = const Duration(milliseconds: 220),
    this.tapSlop = 10,
    this.doubleTapWindow = const Duration(milliseconds: 280),
  });

  /// Multiplicateur doigt → pointeur, à vitesse lente.
  final double sensitivity;

  /// Gain supplémentaire quand le doigt va vite : jusqu'à × (1 + acceleration).
  /// Lent = précis, rapide = traverse l'écran.
  final double acceleration;

  /// Gain pour un doigt à [speed] px/ms.
  double gain(double speed) {
    final t = ((speed - 0.25) / 1.25).clamp(0.0, 1.0);
    return sensitivity * (1 + acceleration * t);
  }

  TrackpadSettings copyWith({double? sensitivity}) => TrackpadSettings(
        sensitivity: sensitivity ?? this.sensitivity,
        acceleration: acceleration,
        pixelsPerNotch: pixelsPerNotch,
        tapMaxDuration: tapMaxDuration,
        tapSlop: tapSlop,
        doubleTapWindow: doubleTapWindow,
      );

  /// Distance de glissement à deux doigts pour un cran de molette.
  final double pixelsPerNotch;
  final Duration tapMaxDuration;
  final double tapSlop;

  /// Délai entre un tap et un nouvel appui pour démarrer un glisser-déposer.
  final Duration doubleTapWindow;
}

enum _Mode { idle, pointer, drag, twoFinger }

/// Interprète les doigts posés sur le trackpad (pur, testé) :
/// - 1 doigt qui glisse → déplacement ;
/// - tap → clic gauche ; tap à 2 doigts → clic droit ;
/// - 2 doigts qui glissent → défilement (sens naturel) ;
/// - tap puis appui maintenu qui glisse → glisser-déposer (bouton gauche maintenu).
class TrackpadEngine {
  TrackpadEngine(this.sink, {this.settings = const TrackpadSettings()});

  final TrackpadSink sink;

  /// Modifiable à chaud (réglage de vitesse).
  TrackpadSettings settings;

  final _pointers = <int, Offset>{};
  final _lastAt = <int, Duration>{};
  _Mode _mode = _Mode.idle;
  Duration _downAt = Duration.zero;
  Offset _downPos = Offset.zero;
  double _travel = 0;
  int _maxFingers = 0;
  Duration? _lastTapAt;
  Offset? _lastTapPos;

  void down(int id, Offset pos, Duration t) {
    _pointers[id] = pos;
    _lastAt[id] = t;
    if (_pointers.length == 1) {
      _downAt = t;
      _downPos = pos;
      _travel = 0;
      _maxFingers = 1;
      final lastTap = _lastTapAt;
      final recentTap = lastTap != null &&
          t - lastTap <= settings.doubleTapWindow &&
          (_lastTapPos! - pos).distance <= settings.tapSlop * 4;
      _mode = recentTap ? _Mode.drag : _Mode.pointer;
      if (_mode == _Mode.drag) sink.button(MouseButton.left, down: true);
    } else {
      _maxFingers = max(_maxFingers, _pointers.length);
      if (_mode == _Mode.drag) sink.button(MouseButton.left, down: false);
      _mode = _Mode.twoFinger;
    }
  }

  void move(int id, Offset pos, Duration t) {
    final prev = _pointers[id];
    if (prev == null) return;
    _pointers[id] = pos;
    final delta = pos - prev;
    final dtMs = max(1, (t - (_lastAt[id] ?? t)).inMicroseconds / 1000);
    _lastAt[id] = t;
    switch (_mode) {
      case _Mode.pointer:
      case _Mode.drag:
        _travel += delta.distance;
        final g = settings.gain(delta.distance / dtMs);
        sink.move(delta.dx * g, delta.dy * g);
      case _Mode.twoFinger:
        // Moyenne des doigts : chaque doigt contribue pour moitié.
        final share = delta / _pointers.length.toDouble();
        _travel += share.distance;
        // Sens naturel : doigts vers le haut → contenu qui défile vers le bas.
        sink.scroll(-share.dx / settings.pixelsPerNotch, -share.dy / settings.pixelsPerNotch);
      case _Mode.idle:
        break;
    }
  }

  void up(int id, Duration t) {
    _lastAt.remove(id);
    if (_pointers.remove(id) == null) return;
    if (_pointers.isNotEmpty) return;

    final quick = t - _downAt <= settings.tapMaxDuration && _travel <= settings.tapSlop;
    final mode = _mode;
    _mode = _Mode.idle;
    switch (mode) {
      case _Mode.pointer:
        if (quick) {
          sink.click(MouseButton.left);
          _lastTapAt = t;
          _lastTapPos = _downPos;
        } else {
          _lastTapAt = null;
        }
      case _Mode.drag:
        sink.button(MouseButton.left, down: false);
        // Tap-tap sans glisser = double clic (bouton relâché aussitôt).
        _lastTapAt = null;
      case _Mode.twoFinger:
        if (quick && _maxFingers == 2) sink.click(MouseButton.right);
        _lastTapAt = null;
      case _Mode.idle:
        break;
    }
  }

  /// Annulation système (appel entrant, etc.) : on relâche tout.
  void cancel() {
    if (_mode == _Mode.drag) sink.button(MouseButton.left, down: false);
    _pointers.clear();
    _mode = _Mode.idle;
    _lastTapAt = null;
  }
}
