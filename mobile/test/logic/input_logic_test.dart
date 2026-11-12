
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/modules/input/input_service.dart';
import 'package:pegasus/src/modules/keyboard/keyboard_diff.dart';
import 'package:pegasus/src/modules/trackpad/trackpad_engine.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

class _Sink implements TrackpadSink {
  final log = <String>[];
  double mx = 0, my = 0, sx = 0, sy = 0;

  @override
  void move(double dx, double dy) {
    mx += dx;
    my += dy;
  }

  @override
  void scroll(double dx, double dy) {
    sx += dx;
    sy += dy;
  }

  @override
  void click(MouseButton button) => log.add('click ${button.name}');

  @override
  void button(MouseButton button, {required bool down}) => log.add('${button.name} ${down ? 'down' : 'up'}');
}

class _Sender implements RemoteSender {
  final log = <String>[];

  @override
  void command(String op, Map<String, Object?> data) => log.add('$op $data');

  @override
  Future<void> request(String op, Map<String, Object?> data) async => log.add('$op $data');
}

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  group('TrackpadEngine', () {
    late _Sink sink;
    late TrackpadEngine e;
    setUp(() {
      sink = _Sink();
      e = TrackpadEngine(sink, settings: const TrackpadSettings(sensitivity: 2, acceleration: 0, pixelsPerNotch: 20));
    });

    test('1 doigt qui glisse → déplacement × sensibilité, pas de clic', () {
      e.down(1, Offset.zero, ms(0));
      e.move(1, const Offset(10, -5), ms(30));
      e.move(1, const Offset(30, -5), ms(60));
      e.up(1, ms(400));
      expect((sink.mx, sink.my), (60.0, -10.0));
      expect(sink.log, isEmpty);
    });

    test('accélération : un geste rapide va plus loin qu’un lent, à distance égale', () {
      double travel(Duration step) {
        final s = _Sink();
        final eng = TrackpadEngine(s, settings: const TrackpadSettings(sensitivity: 2, acceleration: 1.5));
        eng.down(1, Offset.zero, Duration.zero);
        for (var i = 1; i <= 10; i++) {
          eng.move(1, Offset(i * 10.0, 0), step * i);
        }
        return s.mx;
      }

      final slow = travel(const Duration(milliseconds: 100)); // 0,1 px/ms
      final fast = travel(const Duration(milliseconds: 5)); // 2 px/ms
      expect(slow, closeTo(200, 1e-6), reason: 'lent = gain de base, précis');
      expect(fast, closeTo(500, 1e-6), reason: 'rapide = × (1 + 1,5)');
    });

    test('gain : progressif entre lent et rapide', () {
      const s = TrackpadSettings(sensitivity: 2, acceleration: 1.5);
      expect(s.gain(0.1), 2);
      expect(s.gain(0.875), closeTo(3.5, 1e-9));
      expect(s.gain(5), 5);
    });

    test('tap → clic gauche', () {
      e.down(1, const Offset(50, 50), ms(0));
      e.move(1, const Offset(52, 51), ms(50));
      e.up(1, ms(120));
      expect(sink.log, ['click left']);
    });

    test('appui long sans bouger → pas de clic', () {
      e.down(1, Offset.zero, ms(0));
      e.up(1, ms(600));
      expect(sink.log, isEmpty);
    });

    test('tap à 2 doigts → clic droit', () {
      e.down(1, const Offset(10, 10), ms(0));
      e.down(2, const Offset(60, 10), ms(20));
      e.up(1, ms(110));
      e.up(2, ms(130));
      expect(sink.log, ['click right']);
    });

    test('2 doigts qui glissent → défilement en sens naturel, pas de déplacement', () {
      e.down(1, const Offset(10, 100), ms(0));
      e.down(2, const Offset(60, 100), ms(10));
      // Les deux doigts montent de 40 px.
      e.move(1, const Offset(10, 60), ms(50));
      e.move(2, const Offset(60, 60), ms(55));
      e.up(1, ms(300));
      e.up(2, ms(310));
      expect(sink.sy, closeTo(2.0, 1e-9)); // 40 px / 20 px par cran, vers le bas
      expect(sink.mx, 0);
      expect(sink.log, isEmpty);
    });

    test('tap puis appui maintenu qui glisse → glisser-déposer', () {
      e.down(1, const Offset(50, 50), ms(0));
      e.up(1, ms(100)); // tap
      e.down(1, const Offset(52, 50), ms(250)); // appui rapide au même endroit
      e.move(1, const Offset(100, 80), ms(400));
      e.up(1, ms(800));
      expect(sink.log, ['click left', 'left down', 'left up']);
      expect(sink.mx, closeTo(96, 1e-9));
    });

    test('tap trop tardif → pas de glisser-déposer', () {
      e.down(1, Offset.zero, ms(0));
      e.up(1, ms(100));
      e.down(1, Offset.zero, ms(1000));
      e.move(1, const Offset(20, 0), ms(1100));
      e.up(1, ms(1500));
      expect(sink.log, ['click left']);
    });

    test('annulation pendant un glisser → bouton relâché', () {
      e.down(1, Offset.zero, ms(0));
      e.up(1, ms(100));
      e.down(1, Offset.zero, ms(200));
      e.cancel();
      expect(sink.log, ['click left', 'left down', 'left up']);
    });
  });

  group('diffText (frappe en direct)', () {
    test('ajout en fin', () => expect(diffText('Bonj', 'Bonjour'), [const TypeText('our')]));
    test('retour arrière', () => expect(diffText('Bonjour', 'Bonj'), [const PressKey('backspace', 3)]));
    test('correction automatique d’un mot', () {
      expect(diffText('je sius', 'je suis '), [const PressKey('backspace', 3), const TypeText('uis ')]);
    });
    test('modification au milieu : curseur déplacé puis remis', () {
      expect(diffText('chat noir', 'chien noir'), [
        const PressKey('left', 5),
        const PressKey('backspace', 2),
        const TypeText('ien'),
        const PressKey('right', 5),
      ]);
    });
    test('emoji = un seul retour arrière', () {
      expect(diffText('ok 👍🏽', 'ok '), [const PressKey('backspace', 1)]);
    });
    test('identique → rien', () => expect(diffText('abc', 'abc'), isEmpty));
  });

  group('InputService', () {
    test('mouvements regroupés : un seul envoi par intervalle', () {
      fakeAsync((async) {
        final sender = _Sender();
        final s = InputService(sender);
        for (var i = 0; i < 10; i++) {
          s.move(1.234, -0.5);
        }
        expect(sender.log, isEmpty);
        async.elapse(const Duration(milliseconds: 15));
        expect(sender.log, ['input.move {dx: 12.34, dy: -5.0}']);
        async.elapse(const Duration(milliseconds: 100));
        expect(sender.log, hasLength(1));
      });
    });

    test('un clic envoie d’abord le déplacement en attente', () {
      fakeAsync((async) {
        final sender = _Sender();
        final s = InputService(sender);
        s.move(5, 0);
        s.click(MouseButton.left);
        async.flushMicrotasks();
        expect(sender.log, ['input.move {dx: 5.0, dy: 0.0}', 'input.click {button: left, count: 1}']);
      });
    });

    test('requêtes clavier dans l’ordre ; repeat découpé par 100', () async {
      final sender = _Sender();
      final s = InputService(sender);
      unawaited(s.key('backspace', repeat: 250));
      unawaited(s.text('abc'));
      await s.key('tab', modifiers: [KeyModifier.alt]);
      expect(sender.log, [
        'input.key {key: backspace, modifiers: [], repeat: 100}',
        'input.key {key: backspace, modifiers: [], repeat: 100}',
        'input.key {key: backspace, modifiers: [], repeat: 50}',
        'input.text {text: abc}',
        'input.key {key: tab, modifiers: [alt]}',
      ]);
    });

    test('texte de plus de 1000 caractères découpé', () async {
      final sender = _Sender();
      await InputService(sender).text('x' * 2500);
      expect(sender.log, hasLength(3));
    });
  });
}

void unawaited(Future<void> f) {}
