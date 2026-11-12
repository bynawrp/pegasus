import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import '../../core/providers.dart';

/// Envoi vers l'agent (remplacé par un enregistreur dans les tests).
abstract class RemoteSender {
  void command(String op, Map<String, Object?> data);
  Future<void> request(String op, Map<String, Object?> data);
}

class LinkSender implements RemoteSender {
  LinkSender(this._ref);
  final Ref _ref;

  @override
  void command(String op, Map<String, Object?> data) => _ref.read(linkProvider).command(op, data);

  @override
  Future<void> request(String op, Map<String, Object?> data) => _ref.read(linkProvider).request(op, data);
}

final remoteSenderProvider = Provider<RemoteSender>(LinkSender.new);

final inputServiceProvider = Provider<InputService>((ref) {
  final service = InputService(ref.read(remoteSenderProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Module `input` côté app : regroupe les mouvements (≤ ~80 envois/s,
/// spec §8) et sérialise les requêtes clavier pour garder l'ordre de frappe.
class InputService {
  InputService(this._sender, {this.flushInterval = const Duration(milliseconds: 12)});

  final RemoteSender _sender;
  final Duration flushInterval;

  double _mx = 0, _my = 0, _sx = 0, _sy = 0;
  Timer? _timer;
  Future<void> _queue = Future.value();

  void move(double dx, double dy) {
    _mx += dx;
    _my += dy;
    _schedule();
  }

  void scroll(double dx, double dy) {
    _sx += dx;
    _sy += dy;
    _schedule();
  }

  void _schedule() => _timer ??= Timer(flushInterval, flush);

  /// Envoie le cumul en attente (appelé par le minuteur, et avant un clic
  /// pour que le pointeur soit à jour).
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_mx != 0 || _my != 0) {
      _sender.command('input.move', {'dx': _round(_mx), 'dy': _round(_my)});
      _mx = _my = 0;
    }
    if (_sx != 0 || _sy != 0) {
      _sender.command('input.scroll', {'dx': _round(_sx), 'dy': _round(_sy)});
      _sx = _sy = 0;
    }
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  void button(MouseButton b, {required bool down}) {
    flush();
    _sender.command('input.button', {'button': b.name, 'state': down ? 'down' : 'up'});
  }

  Future<void> click(MouseButton b, {int count = 1}) {
    flush();
    return _enqueue('input.click', {'button': b.name, 'count': count});
  }

  // Les morceaux sont tous mis en file d'un coup (sans `await` entre eux)
  // pour qu'aucune autre frappe ne s'intercale.

  Future<void> text(String text) {
    // Découpe en morceaux de 1000 caractères max (spec §8).
    final runes = text.runes.toList();
    return Future.wait([
      for (var i = 0; i < runes.length; i += InputLimits.maxTextLength)
        _enqueue('input.text', {
          'text': String.fromCharCodes(runes.sublist(i, (i + InputLimits.maxTextLength).clamp(0, runes.length))),
        }),
    ]);
  }

  Future<void> key(String key, {List<KeyModifier> modifiers = const [], int repeat = 1}) {
    final chunks = <int>[];
    for (var left = repeat; left > 0; left -= InputLimits.maxRepeat) {
      chunks.add(left.clamp(1, InputLimits.maxRepeat));
    }
    return Future.wait([
      for (final n in chunks)
        _enqueue('input.key', {
          'key': key,
          'modifiers': [for (final m in modifiers) m.name],
          if (n > 1) 'repeat': n,
        }),
    ]);
  }

  /// Les requêtes partent une par une, dans l'ordre ; une erreur n'arrête pas la file.
  Future<void> _enqueue(String op, Map<String, Object?> data) {
    final next = _queue.then((_) => _sender.request(op, data));
    _queue = next.catchError((_) {});
    return next;
  }

  void dispose() => _timer?.cancel();
}
