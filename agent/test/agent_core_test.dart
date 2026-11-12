import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_agent/src/core/agent_controller.dart';
import 'package:pegasus_agent/src/core/agent_store.dart';
import 'package:pegasus_agent/src/core/secret_protector.dart';
import 'package:pegasus_agent/src/platform/input_controller.dart';
import 'package:pegasus_agent/src/platform/system_controller.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('pegasus_agent_test');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
  return dir;
}

Future<AgentViewState> _until(ProviderContainer c, bool Function(AgentViewState) test) async {
  if (test(c.read(agentControllerProvider))) return c.read(agentControllerProvider);
  final completer = Completer<AgentViewState>();
  final sub = c.listen(agentControllerProvider, (_, next) {
    if (test(next) && !completer.isCompleted) completer.complete(next);
  });
  try {
    return await completer.future.timeout(const Duration(seconds: 10));
  } finally {
    sub.close();
  }
}

const _tel = DeviceDescriptor(id: 'tel-1', name: 'Pixel', platform: 'android');

void main() {
  group('SecretProtector', () {
    test(
      'DPAPI : aller-retour, texte clair absent',
      () {
        final p = DpapiProtector();
        final stored = p.protect('secret-très-privé');
        expect(stored, startsWith('dpapi:'));
        expect(stored, isNot(contains('secret')));
        expect(p.unprotect(stored), 'secret-très-privé');
      },
      skip: Platform.isWindows ? false : 'Windows uniquement',
    );

    test('Plain : aller-retour', () {
      const p = PlainProtector();
      expect(p.unprotect(p.protect('x')), 'x');
    });
  });

  group('AgentStore', () {
    test('crée une identité au premier lancement puis la relit', () async {
      final dir = await _tempDir();
      final first = await AgentStore(dir).loadOrCreate(defaultName: 'PC');
      final again = await AgentStore(dir).loadOrCreate(defaultName: 'autre');
      expect(again.identity.agentId, first.identity.agentId);
      expect(again.identity.fingerprint, first.identity.fingerprint);
      expect(again.identity.name, 'PC');
    });

    test('appareils persistés, secrets chiffrés sur disque', () async {
      final dir = await _tempDir();
      final store = AgentStore(dir);
      final data = await store.loadOrCreate(defaultName: 'PC');
      final device = PairedDevice(
          id: 'd1', name: 'Tel', platform: 'android', secret: 'SECRET-123', pairedAt: DateTime(2026));
      await store.save(AgentData(identity: data.identity, devices: [device]));
      final raw = await store.file.readAsString();
      if (Platform.isWindows) {
        expect(raw, isNot(contains('SECRET-123')));
        expect(raw, isNot(contains('EC PRIVATE KEY')));
      }
      final loaded = await AgentStore(dir).loadOrCreate(defaultName: 'PC');
      expect(loaded.devices.single.secret, 'SECRET-123');
      expect(loaded.devices.single.name, 'Tel');
    });

    test('fichier corrompu → mis de côté, nouvelle identité', () async {
      final dir = await _tempDir();
      await File('${dir.path}/agent.json').writeAsString('{pas du json');
      final data = await AgentStore(dir).loadOrCreate(defaultName: 'PC');
      expect(data.identity.agentId, isNotEmpty);
      expect(dir.listSync().where((f) => f.path.contains('.bak-')), hasLength(1));
    });
  });

  group('AgentController (serveur réel)', () {
    late ProviderContainer container;
    late Directory dir;

    ProviderContainer makeContainer({int port = 0, Directory? directory}) {
      final c = ProviderContainer(overrides: [
        agentDirectoryProvider.overrideWith((ref) async => directory ?? dir),
        inputControllerProvider.overrideWithValue(RecordingInputController()),
        systemControllerProvider.overrideWithValue(RecordingSystemController()),
        agentServerConfigProvider.overrideWithValue(
          AgentServerConfig(port: port, address: InternetAddress.loopbackIPv4),
        ),
      ]);
      addTearDown(c.dispose);
      c.read(agentControllerProvider);
      return c;
    }

    setUp(() async {
      dir = await _tempDir();
      container = makeContainer();
    });

    Future<AgentViewState> running() =>
        _until(container, (s) => s.status == AgentStatus.running && s.pairing != null);

    Future<PegasusConnection> connect(AgentViewState s) async {
      final server = container.read(agentControllerProvider.notifier).server!;
      final conn = await PegasusClient.connect(
          host: '127.0.0.1', port: server.port, fingerprint: s.fingerprint);
      addTearDown(conn.close);
      return conn;
    }

    Future<PegasusConnection> pairAndAuth() async {
      final s = await running();
      final conn = await connect(s);
      final r = await conn.pair(token: s.pairing!.token, device: _tel);
      await conn.authenticate(agentId: r.agentId, deviceId: _tel.id, deviceSecret: r.deviceSecret);
      return conn;
    }

    test('démarre et génère un QR valide', () async {
      final s = await running();
      expect(s.agentId, isNotEmpty);
      expect(s.pairing!.code, matches(RegExp(r'^\d{6}$')));
      if (s.addresses.isNotEmpty) {
        final invite = PairingInvite.parse(s.invite.toString());
        expect(invite.fingerprint, s.fingerprint);
        expect(invite.token, s.pairing!.token);
      }
    });

    test('appairage → appareil connecté, persisté ; jeton consommé', () async {
      await pairAndAuth();
      final s = await _until(container, (s) => s.connected.contains('tel-1'));
      expect(s.devices.single.name, 'Pixel');
      expect(s.pairing, isNull);
      expect(s.activity.map((a) => a.label), containsAll(['Pixel associé', 'Pixel connecté']));
      await container.read(agentControllerProvider.notifier).flush();
      final json = jsonDecode(await File('${dir.path}/agent.json').readAsString()) as Map;
      expect((json['devices'] as List).single['id'], 'tel-1');
    });

    test('déconnexion du téléphone → retiré des connectés', () async {
      final conn = await pairAndAuth();
      await _until(container, (s) => s.connected.contains('tel-1'));
      await conn.close();
      final s = await _until(container, (s) => s.connected.isEmpty);
      expect(s.activity.first.label, 'Pixel déconnecté');
    });

    test('pause → évènement reçu par le téléphone', () async {
      final conn = await pairAndAuth();
      final evt = conn.events.firstWhere((e) => e.op == 'session.paused');
      container.read(agentControllerProvider.notifier).setPaused(true);
      expect((await evt).data['paused'], isTrue);
      expect(container.read(agentControllerProvider).paused, isTrue);
    });

    test('renommer un appareil', () async {
      await pairAndAuth();
      await _until(container, (s) => s.devices.isNotEmpty);
      container.read(agentControllerProvider.notifier).rename('tel-1', '  Mon Pixel  ');
      final s = await _until(container, (s) => s.devices.single.name == 'Mon Pixel');
      expect(s.devices.single.name, 'Mon Pixel');
    });

    test('révoquer → connexion fermée en 4403, appareil retiré', () async {
      final conn = await pairAndAuth();
      await _until(container, (s) => s.connected.contains('tel-1'));
      await container.read(agentControllerProvider.notifier).revoke('tel-1');
      expect(await conn.done.timeout(const Duration(seconds: 5)), CloseCodes.revoked);
      final s = await _until(container, (s) => s.devices.isEmpty && s.connected.isEmpty);
      expect(s.activity.map((a) => a.label), contains('Pixel révoqué'));
    });

    test('5 codes faux → verrouillé, puis nouveau code', () async {
      final s = await running();
      final conn = await connect(s);
      for (var i = 0; i < 5; i++) {
        await conn
            .pair(code: 'x$i', device: _tel)
            .then<void>((_) {}, onError: (_) {});
      }
      await _until(container, (s) => s.pairingLocked && s.pairing == null);
      container.read(agentControllerProvider.notifier).renewPairing();
      await _until(container, (s) => !s.pairingLocked && s.pairing != null);
    });

    test('appareil retrouvé après redémarrage de l’agent', () async {
      await pairAndAuth();
      await _until(container, (s) => s.devices.isNotEmpty);
      await container.read(agentControllerProvider.notifier).flush();
      container.dispose();
      final c2 = makeContainer();
      final s = await _until(c2, (s) => s.status == AgentStatus.running);
      expect(s.devices.single.id, 'tel-1');
    });

    test('port déjà utilisé → état erreur lisible', () async {
      final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(blocker.close);
      final c2 = makeContainer(port: blocker.port, directory: await _tempDir());
      final s = await _until(c2, (s) => s.status == AgentStatus.error);
      expect(s.error, contains('${blocker.port}'));
    });
  });
}
