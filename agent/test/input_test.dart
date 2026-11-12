import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_agent/src/modules/input/input_module.dart';
import 'package:pegasus_agent/src/platform/input_controller.dart';
import 'package:pegasus_agent/src/platform/windows/windows_input.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

const _down = 0, _up = WinInput.keyUp;

void main() {
  group('Structures Win32 (x64)', () {
    test('INPUT fait 40 octets, MOUSEINPUT 32, KEYBDINPUT 24', () {
      expect(sizeOf<INPUT>(), 40);
      expect(sizeOf<MOUSEINPUT>(), 32);
      expect(sizeOf<KEYBDINPUT>(), 24);
    });
  });

  test(
    'SendInput réel : Windows accepte un aller-retour de souris d’1 pixel',
    () {
      final win = WindowsInputController();
      final sent = win.dispatch([
        const RawMouse(dx: 1, flags: WinInput.move),
        const RawMouse(dx: -1, flags: WinInput.move),
      ]);
      expect(sent, 2);
    },
    // Les runners CI n'ont pas de session interactive : SendInput y est refusé.
    skip: !Platform.isWindows
        ? 'Windows uniquement'
        : Platform.environment['CI'] == 'true'
            ? 'Pas de bureau interactif en CI'
            : false,
  );

  group('WindowsInputPlanner', () {
    late WindowsInputPlanner p;
    setUp(() => p = WindowsInputPlanner());

    test('déplacement : décimales cumulées, rien perdu', () {
      expect(p.move(0.4, -0.4), isEmpty);
      expect(p.move(0.4, -0.4), isEmpty);
      expect(p.move(0.4, -0.4), [const RawMouse(dx: 1, dy: -1, flags: WinInput.move)]);
      var total = 0;
      final q = WindowsInputPlanner();
      for (var i = 0; i < 100; i++) {
        for (final e in q.move(0.37, 0)) {
          total += (e as RawMouse).dx;
        }
      }
      // Le reste flottant (≈ 0,9999) est conservé et sort au mouvement suivant.
      for (final e in q.move(0.01, 0)) {
        total += (e as RawMouse).dx;
      }
      expect(total, 37);
    });

    test('défilement : dy > 0 = vers le bas (molette négative), crans partiels cumulés', () {
      expect(p.scroll(0, 1), [const RawMouse(flags: WinInput.wheel, data: -120)]);
      expect(p.scroll(0, -0.5), [const RawMouse(flags: WinInput.wheel, data: 60)]);
      expect(p.scroll(1, 0), [const RawMouse(flags: WinInput.hWheel, data: 120)]);
      expect(p.scroll(0, 0.004), isEmpty);
    });

    test('clics : appui puis relâche, double clic', () {
      expect(p.click(MouseButton.left), [
        const RawMouse(flags: WinInput.leftDown),
        const RawMouse(flags: WinInput.leftUp),
      ]);
      expect(p.click(MouseButton.right, count: 2), hasLength(4));
      expect(p.button(MouseButton.middle, down: true), [const RawMouse(flags: WinInput.middleDown)]);
    });

    test('texte Unicode : une paire appui/relâche par unité UTF-16, retour à la ligne = Entrée', () {
      final e = p.text('é😀\n');
      // é (1) + 😀 (2 unités) = 3 × 2 évènements + Entrée (2).
      expect(e, hasLength(8));
      expect(e[0], const RawKey(scan: 0xE9, flags: WinInput.unicode));
      expect(e[1], const RawKey(scan: 0xE9, flags: WinInput.unicode | _up));
      expect(e[2], const RawKey(scan: 0xD83D, flags: WinInput.unicode));
      expect(e[6], const RawKey(vk: WinInput.vkReturn, flags: _down));
      expect(e[7], const RawKey(vk: WinInput.vkReturn, flags: _up));
    });

    test('Alt+Tab : modificateur appuyé, touche, modificateur relâché', () {
      expect(p.key('tab', [KeyModifier.alt]), [
        const RawKey(vk: WinInput.vkMenu, flags: _down),
        const RawKey(vk: 0x09, flags: _down),
        const RawKey(vk: 0x09, flags: _up),
        const RawKey(vk: WinInput.vkMenu, flags: _up),
      ]);
    });

    test('Ctrl+Maj+Échap : relâchés dans l’ordre inverse', () {
      final e = p.key('escape', [KeyModifier.ctrl, KeyModifier.shift]);
      expect(e.map((k) => (k as RawKey).vk).toList(),
          [WinInput.vkControl, WinInput.vkShift, 0x1B, 0x1B, WinInput.vkShift, WinInput.vkControl]);
    });

    test('repeat : la touche est répétée, modificateurs une seule fois', () {
      final e = p.key('left', [KeyModifier.shift], repeat: 3);
      expect(e, hasLength(2 + 3 * 2));
      expect((e.first as RawKey).vk, WinInput.vkShift);
      expect((e.last as RawKey).vk, WinInput.vkShift);
    });

    test('touches étendues (flèches, Suppr, Win)', () {
      expect(p.key('up', const []).first, const RawKey(vk: 0x26, flags: WinInput.extended));
      expect(p.key('delete', const []).first, const RawKey(vk: 0x2E, flags: WinInput.extended));
      expect(p.key('win', const []).first, const RawKey(vk: 0x5B, flags: WinInput.extended));
    });

    test('toutes les touches de la spec ont un code Windows', () {
      for (final k in InputKeys.all) {
        expect(WinInput.keys.containsKey(k), isTrue, reason: k);
      }
      expect(WinInput.keys['a']!.$1, 0x41);
      expect(WinInput.keys['f12']!.$1, 0x7B);
      expect(WinInput.keys['0']!.$1, 0x30);
    });
  });

  group('Module input via le serveur (bout en bout)', () {
    late AgentServer server;
    late RecordingInputController input;
    late PegasusConnection conn;

    setUp(() async {
      final identity = AgentIdentity.generate(name: 'PC');
      server = AgentServer(
        identity: identity,
        config: AgentServerConfig(port: 0, address: InternetAddress.loopbackIPv4),
      );
      input = RecordingInputController();
      registerInputModule(server, input);
      await server.start();
      addTearDown(server.dispose);
      final secret = server.pairing.renew();
      conn = await PegasusClient.connect(host: '127.0.0.1', port: server.port, fingerprint: identity.fingerprint);
      addTearDown(conn.close);
      final r = await conn.pair(
          token: secret.token, device: const DeviceDescriptor(id: 'd', name: 'T', platform: 'ios'));
      await conn.authenticate(agentId: r.agentId, deviceId: 'd', deviceSecret: r.deviceSecret);
    });

    Matcher badRequest() =>
        throwsA(isA<RequestFailedException>().having((e) => e.code, 'code', ErrorCode.badRequest));

    test('commandes et requêtes arrivent au contrôleur, dans l’ordre', () async {
      conn.command('input.move', {'dx': 3.5, 'dy': -1});
      conn.command('input.scroll', {'dy': 2});
      conn.command('input.button', {'button': 'left', 'state': 'down'});
      conn.command('input.button', {'button': 'left', 'state': 'up'});
      await conn.request('input.click', {'button': 'right', 'count': 1});
      await conn.request('input.text', {'text': 'Salut 👋'});
      await conn.request('input.key', {'key': 'tab', 'modifiers': ['alt']});
      await conn.request('input.key', {'key': 'backspace', 'repeat': 8});
      expect(input.calls, [
        'move 3.5 -1.0',
        'scroll 0.0 2.0',
        'button left down',
        'button left up',
        'click right 1',
        'text Salut 👋',
        'key alt+tab',
        'key backspace x8',
      ]);
    });

    test('données invalides → bad_request, rien n’est exécuté', () async {
      await expectLater(conn.request('input.key', {'key': 'f13'}), badRequest());
      await expectLater(conn.request('input.text', {'text': 'x' * 1001}), badRequest());
      await expectLater(conn.request('input.click', {'count': 5}), badRequest());
      expect(input.calls, isEmpty);
    });

    test('commande invalide ignorée sans couper la connexion', () async {
      conn.command('input.move', {'dx': 'beaucoup'});
      conn.command('input.button', {'button': 'aucun', 'state': 'down'});
      await conn.request('input.click', const {});
      expect(input.calls, ['click left 1']);
    });

    test('module désactivé → forbidden, commandes ignorées', () async {
      server.setModule('input', false);
      conn.command('input.move', {'dx': 1, 'dy': 1});
      await expectLater(conn.request('input.text', {'text': 'a'}),
          throwsA(isA<RequestFailedException>().having((e) => e.code, 'code', ErrorCode.forbidden)));
      expect(input.calls, isEmpty);
    });

    test('agent en pause → paused, commandes ignorées', () async {
      server.setPaused(true);
      conn.command('input.move', {'dx': 1, 'dy': 1});
      await expectLater(conn.request('input.key', {'key': 'a'}),
          throwsA(isA<RequestFailedException>().having((e) => e.code, 'code', ErrorCode.paused)));
      expect(input.calls, isEmpty);
    });

    test('rafale de 60 déplacements/s sans perte', () async {
      for (var i = 0; i < 60; i++) {
        conn.command('input.move', {'dx': 1, 'dy': 0});
      }
      await conn.request('input.click', const {});
      expect(input.calls.where((c) => c.startsWith('move')), hasLength(60));
    });
  });
}
