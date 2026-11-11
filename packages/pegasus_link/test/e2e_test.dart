// Tests de bout en bout : vrai serveur TLS de l'agent + vrai client de l'app
// sur la boucle locale. Chaque règle de docs/protocol.md y est vérifiée.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:test/test.dart';

final _identity = AgentIdentity.generate(name: 'PC-Test');

const _phone = DeviceDescriptor(id: 'device-1', name: 'Téléphone 1', platform: 'android');
const _phone2 = DeviceDescriptor(id: 'device-2', name: 'Téléphone 2', platform: 'ios');

Future<AgentServer> _server({
  AgentServerConfig config = const AgentServerConfig(),
  List<PairedDevice> devices = const [],
  PairingManager? pairing,
}) async {
  final server = AgentServer(
    identity: _identity,
    config: AgentServerConfig(
      port: 0,
      address: InternetAddress.loopbackIPv4,
      handshakeTimeout: config.handshakeTimeout,
      maxDevices: config.maxDevices,
      requestsPerSecond: config.requestsPerSecond,
      commandsPerSecond: config.commandsPerSecond,
      isAllowedAddress: config.isAllowedAddress,
    ),
    devices: devices,
    pairing: pairing,
  );
  await server.start();
  addTearDown(server.dispose);
  return server;
}

Future<PegasusConnection> _connect(AgentServer s, {String? fingerprint}) async {
  final c = await PegasusClient.connect(
    host: '127.0.0.1',
    port: s.port,
    fingerprint: fingerprint ?? _identity.fingerprint,
  );
  addTearDown(c.close);
  return c;
}

/// Associe [device] et renvoie le PC tel que mémorisé par l'app.
Future<PairedAgent> _pair(AgentServer s, [DeviceDescriptor device = _phone]) async {
  final secret = s.pairing.renew();
  final c = await _connect(s);
  final r = await c.pair(token: secret.token, device: device);
  await c.close();
  return PairedAgent(
    agentId: r.agentId,
    agentName: r.agentName,
    host: '127.0.0.1',
    port: s.port,
    fingerprint: _identity.fingerprint,
    deviceId: device.id,
    deviceSecret: r.deviceSecret,
  );
}

Future<(PegasusConnection, SessionInfo)> _auth(AgentServer s, PairedAgent a) async {
  final c = await _connect(s);
  final info = await c.authenticate(
      agentId: a.agentId, deviceId: a.deviceId, deviceSecret: a.deviceSecret);
  return (c, info);
}

Matcher _failsWith(ErrorCode code) =>
    throwsA(isA<RequestFailedException>().having((e) => e.code, 'code', code));

Future<LinkState> _until(PegasusLink link, bool Function(LinkState) test) async {
  if (test(link.state)) return link.state;
  return link.states.firstWhere(test).timeout(const Duration(seconds: 10));
}

void main() {
  group('Identité et transport', () {
    test('certificat ECDSA : empreinte stable et sérialisable', () {
      final copy = AgentIdentity.fromJson(_identity.toJson());
      expect(copy.fingerprint, _identity.fingerprint);
      expect(copy.agentId, _identity.agentId);
      expect(PegasusCrypto.fromB64url(_identity.fingerprint).length, 32);
      expect(_identity.privateKeyPem, contains('EC PRIVATE KEY'));
    });

    test('probeFingerprint renvoie l’empreinte du serveur', () async {
      final s = await _server();
      expect(await PegasusClient.probeFingerprint('127.0.0.1', s.port), _identity.fingerprint);
    });

    test('certificat épinglé différent → connexion refusée', () async {
      final s = await _server();
      expect(
        PegasusClient.connect(host: '127.0.0.1', port: s.port, fingerprint: 'AAAA'),
        throwsA(isA<FingerprintMismatchException>()),
      );
    });

    test('adresse source hors réseau local → refusée', () async {
      final s = await _server(config: AgentServerConfig(isAllowedAddress: (_) => false));
      expect(_connect(s), throwsA(isA<WebSocketException>()));
    });

    test('isLocalNetworkAddress', () {
      bool local(String a) => isLocalNetworkAddress(InternetAddress(a));
      for (final a in ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.1', '192.168.1.20',
        '169.254.3.4', '::1', 'fe80::1', 'fd12::1', '::ffff:192.168.1.2']) {
        expect(local(a), isTrue, reason: a);
      }
      for (final a in ['8.8.8.8', '172.32.0.1', '100.64.0.1', '2001:db8::1', '::ffff:8.8.8.8']) {
        expect(local(a), isFalse, reason: a);
      }
    });
  });

  group('Appairage (§3)', () {
    test('jeton QR : succès, appareil enregistré, secret de 32 octets', () async {
      final s = await _server();
      final events = <AgentServerEvent>[];
      s.events.listen(events.add);
      final agent = await _pair(s);
      expect(agent.agentId, _identity.agentId);
      expect(agent.agentName, 'PC-Test');
      expect(PegasusCrypto.fromB64url(agent.deviceSecret).length, 32);
      expect(s.devices.single.id, 'device-1');
      expect(s.devices.single.name, 'Téléphone 1');
      await pumpEventQueue();
      expect(events.whereType<DevicePaired>(), hasLength(1));
    });

    test('code manuel à 6 chiffres', () async {
      final s = await _server();
      final secret = s.pairing.renew();
      final c = await _connect(s);
      final r = await c.pair(code: secret.code, device: _phone);
      expect(r.deviceSecret, isNotEmpty);
    });

    test('jeton à usage unique', () async {
      final s = await _server();
      final secret = s.pairing.renew();
      final c1 = await _connect(s);
      await c1.pair(token: secret.token, device: _phone);
      final c2 = await _connect(s);
      expect(c2.pair(token: secret.token, device: _phone2), _failsWith(ErrorCode.rejected));
    });

    test('mauvais jeton refusé ; 5 échecs → verrouillé même avec le bon', () async {
      final s = await _server();
      final secret = s.pairing.renew();
      final c = await _connect(s);
      for (var i = 0; i < 4; i++) {
        await expectLater(c.pair(code: '000000x', device: _phone), _failsWith(ErrorCode.rejected));
      }
      expect(s.pairing.locked, isFalse);
      await expectLater(c.pair(code: 'bad', device: _phone), _failsWith(ErrorCode.rejected));
      expect(s.pairing.locked, isTrue);
      final c2 = await _connect(s);
      await expectLater(c2.pair(token: secret.token, device: _phone), _failsWith(ErrorCode.rejected));
      // Régénération → de nouveau possible.
      final fresh = s.pairing.renew();
      final c3 = await _connect(s);
      expect((await c3.pair(token: fresh.token, device: _phone)).deviceSecret, isNotEmpty);
    });

    test('jeton expiré (5 min)', () {
      var now = DateTime(2026);
      final m = PairingManager(clock: () => now);
      final secret = m.renew();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(m.current, isNotNull);
      now = now.add(const Duration(seconds: 1));
      expect(m.current, isNull);
      expect(m.consume(token: secret.token), PairingCheck.expired);
    });

    test('pair.request sans appareil → bad_request', () async {
      final s = await _server();
      final secret = s.pairing.renew();
      final c = await _connect(s);
      expect(c.request('pair.request', {'token': secret.token}), _failsWith(ErrorCode.badRequest));
    });

    test('appairage puis authentification sur la même connexion', () async {
      final s = await _server();
      final secret = s.pairing.renew();
      final c = await _connect(s);
      final r = await c.pair(token: secret.token, device: _phone);
      final info = await c.authenticate(
          agentId: r.agentId, deviceId: _phone.id, deviceSecret: r.deviceSecret);
      expect(info.agentName, 'PC-Test');
    });
  });

  group('Authentification (§4)', () {
    test('succès : infos agent, modules et pause', () async {
      final s = await _server();
      final a = await _pair(s);
      final (_, info) = await _auth(s, a);
      expect(info.agentId, _identity.agentId);
      expect(info.os, 'windows');
      expect(info.modules, {'input': true, 'media': true, 'power': true, 'apps': true});
      expect(info.paused, isFalse);
      expect(s.sessions.single.device!.id, 'device-1');
    });

    test('évènements DeviceConnected / DeviceDisconnected', () async {
      final s = await _server();
      final a = await _pair(s);
      final events = <AgentServerEvent>[];
      s.events.listen(events.add);
      final (c, _) = await _auth(s, a);
      await c.close();
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events.whereType<DeviceConnected>().single.device.id, 'device-1');
      expect(events.whereType<DeviceDisconnected>().single.device.id, 'device-1');
      expect(s.sessions, isEmpty);
    });

    test('mauvais secret → fermeture 4401', () async {
      final s = await _server();
      final a = await _pair(s);
      final c = await _connect(s);
      await expectLater(
        c.authenticate(agentId: a.agentId, deviceId: a.deviceId,
            deviceSecret: PegasusCrypto.randomToken()),
        throwsA(isA<ConnectionClosedException>()),
      );
      expect(await c.done, CloseCodes.unauthorized);
    });

    test('appareil inconnu → fermeture 4403', () async {
      final s = await _server();
      final c = await _connect(s);
      await expectLater(
        c.authenticate(agentId: 'x', deviceId: 'inconnu', deviceSecret: PegasusCrypto.randomToken()),
        throwsA(isA<ConnectionClosedException>()),
      );
      expect(await c.done, CloseCodes.revoked);
    });

    test('version de protocole non supportée → 4426', () async {
      final s = await _server();
      final a = await _pair(s);
      final c = await _connect(s);
      unawaited(c.request('session.hello', {
        'deviceId': a.deviceId,
        'protocol': {'min': 2, 'max': 3},
      }).catchError((_) => <String, Object?>{}));
      expect(await c.done, CloseCodes.unsupportedVersion);
    });

    test('nonce à usage unique : rejouer un MAC échoue', () async {
      final s = await _server();
      final a = await _pair(s);
      final c = await _connect(s);
      final hello = await c.request('session.hello', {
        'deviceId': a.deviceId,
        'protocol': {'min': 1, 'max': 1},
      });
      final mac = PegasusCrypto.authMac(deviceSecret: a.deviceSecret,
          nonce: hello['nonce'] as String, agentId: a.agentId, deviceId: a.deviceId);
      await c.request('session.auth', {'mac': mac});
      // Rejeu sur une nouvelle connexion avec un nouveau nonce.
      final c2 = await _connect(s);
      await c2.request('session.hello', {
        'deviceId': a.deviceId,
        'protocol': {'min': 1, 'max': 1},
      });
      unawaited(c2.request('session.auth', {'mac': mac}).catchError((_) => <String, Object?>{}));
      expect(await c2.done, CloseCodes.unauthorized);
    });

    test('opération avant authentification → unauthorized', () async {
      final s = await _server();
      final c = await _connect(s);
      expect(c.request('agent.info'), _failsWith(ErrorCode.unauthorized));
    });

    test('handshake trop long → 4408', () async {
      final s = await _server(
          config: const AgentServerConfig(handshakeTimeout: Duration(milliseconds: 300)));
      final c = await _connect(s);
      expect(await c.done.timeout(const Duration(seconds: 5)), CloseCodes.handshakeTimeout);
    });

    test('message invalide pendant le handshake → 4400', () async {
      final s = await _server();
      final ws = await WebSocket.connect('wss://127.0.0.1:${s.port}/ws',
          customClient: HttpClient(context: SecurityContext(withTrustedRoots: false))
            ..badCertificateCallback = (_, _, _) => true);
      ws.add('pas du json');
      await ws.drain<void>();
      expect(ws.closeCode, CloseCodes.badHandshake);
    });

    test('même appareil connecté deux fois → l’ancienne fermée en 4409', () async {
      final s = await _server();
      final a = await _pair(s);
      final (c1, _) = await _auth(s, a);
      await _auth(s, a);
      expect(await c1.done.timeout(const Duration(seconds: 5)), CloseCodes.replaced);
      await pumpEventQueue();
      expect(s.sessions, hasLength(1));
    });

    test('5 appareils max simultanés', () async {
      final s = await _server(config: const AgentServerConfig(maxDevices: 2));
      final a1 = await _pair(s, _phone);
      final a2 = await _pair(s, _phone2);
      final a3 = await _pair(s, const DeviceDescriptor(id: 'd3', name: 'T3', platform: 'android'));
      await _auth(s, a1);
      await _auth(s, a2);
      await expectLater(_auth(s, a3), throwsA(isA<RequestFailedException>()));
    });
  });

  group('Session authentifiée (§2, §6, §7, §9)', () {
    late AgentServer s;
    late PegasusConnection c;

    setUp(() async {
      s = await _server(config: const AgentServerConfig(requestsPerSecond: 20));
      s.onRequest('power.lock', (_, _) => {'locked': true});
      s.onRequest('apps.boom', (_, _) => throw StateError('boom'));
      s.onRequest('url.open', (_, data) {
        if (data['url'] is! String) throw const OpException(ErrorCode.badRequest, 'url manquante');
        return null;
      });
      (c, _) = await _auth(s, await _pair(s));
    });

    test('agent.info', () async {
      final info = await c.request('agent.info');
      expect(info['name'], 'PC-Test');
      expect(info['paused'], isFalse);
    });

    test('requête traitée et journalisée', () async {
      final logs = <RequestLogged>[];
      s.events.listen((e) { if (e is RequestLogged) logs.add(e); });
      expect(await c.request('power.lock'), {'locked': true});
      await pumpEventQueue();
      expect(logs.single.op, 'power.lock');
      expect(logs.single.module, 'power');
      expect(logs.single.device.id, 'device-1');
    });

    test('op inconnue → not_supported', () async {
      expect(c.request('power.explode'), _failsWith(ErrorCode.notSupported));
    });

    test('OpException → code renvoyé ; exception → internal', () async {
      await expectLater(c.request('url.open'), _failsWith(ErrorCode.badRequest));
      await expectLater(c.request('apps.boom'), _failsWith(ErrorCode.internal));
      // La connexion reste ouverte.
      expect(await c.request('power.lock'), isNotEmpty);
    });

    test('module désactivé → forbidden + évènement session.modules', () async {
      final evt = c.events.firstWhere((e) => e.op == 'session.modules');
      s.setModule('power', false);
      expect((await evt).data['modules'], containsPair('power', false));
      await expectLater(c.request('power.lock'), _failsWith(ErrorCode.forbidden));
      s.setModule('power', true);
      expect(await c.request('power.lock'), isNotEmpty);
    });

    test('pause → paused (sauf agent.*), commandes ignorées, évènement poussé', () async {
      final received = <Map<String, Object?>>[];
      s.onCommand('input.move', (_, d) => received.add(d));
      final evt = c.events.firstWhere((e) => e.op == 'session.paused');
      s.setPaused(true);
      expect((await evt).data['paused'], isTrue);
      await expectLater(c.request('power.lock'), _failsWith(ErrorCode.paused));
      expect((await c.request('agent.info'))['paused'], isTrue);
      c.command('input.move', {'dx': 1, 'dy': 1});
      await c.request('agent.info');
      expect(received, isEmpty);
      s.setPaused(false);
      c.command('input.move', {'dx': 2, 'dy': 3});
      await c.request('agent.info');
      expect(received, [{'dx': 2, 'dy': 3}]);
    });

    test('débit de requêtes limité (20/s) → rate_limited', () async {
      final results = await Future.wait(List.generate(25,
          (_) => c.request('agent.info').then((_) => 'ok', onError: (Object e) =>
              e is RequestFailedException ? e.code.wire : '$e')));
      expect(results.where((r) => r == 'ok'), hasLength(20));
      expect(results.where((r) => r == 'rate_limited'), hasLength(5));
    });

    test('débit de commandes limité (200/s)', () async {
      var count = 0;
      s.onCommand('input.move', (_, _) => count++);
      for (var i = 0; i < 260; i++) {
        c.command('input.move', {'dx': 1, 'dy': 0});
      }
      await c.request('agent.info').catchError((_) => <String, Object?>{});
      expect(count, 200);
    });

    test('révocation → fermeture 4403 et appareil retiré', () async {
      await s.revoke('device-1');
      expect(await c.done.timeout(const Duration(seconds: 5)), CloseCodes.revoked);
      expect(s.devices, isEmpty);
    });

    test('renommer un appareil', () {
      s.renameDevice('device-1', 'Pixel');
      expect(s.devices.single.name, 'Pixel');
    });

    test('message > 64 Kio → fermeture 1009', () async {
      unawaited(c.request('url.open', {'url': 'x' * (maxMessageBytes + 10)})
          .catchError((_) => <String, Object?>{}));
      expect(await c.done.timeout(const Duration(seconds: 5)), WebSocketStatus.messageTooBig);
    });
  });

  group('Reconnexion (§5)', () {
    test('délais 1, 2, 4, 8, 16, 30 s max ±20 %', () {
      final r = Random(1);
      const bases = [1, 2, 4, 8, 16, 30, 30, 30];
      for (var i = 0; i < bases.length; i++) {
        for (var k = 0; k < 20; k++) {
          final ms = reconnectDelay(i, r).inMilliseconds;
          expect(ms, inInclusiveRange(bases[i] * 800, bases[i] * 1200), reason: 'tentative $i');
        }
      }
    });

    test('PegasusLink : connexion, évènements, puis reconnexion après redémarrage', () async {
      final s = await _server();
      final a = await _pair(s);
      final link = PegasusLink(connectTimeout: const Duration(seconds: 2));
      addTearDown(link.dispose);
      link.start(a);
      final connected = await _until(link, (st) => st.isConnected);
      expect(connected.info!.agentName, 'PC-Test');

      s.setPaused(true);
      expect((await _until(link, (st) => st.info?.paused == true)).info!.paused, isTrue);
      s.setPaused(false);

      // Coupure côté agent : l'app attend puis se reconnecte.
      final port = s.port;
      await s.stop();
      await _until(link, (st) => st.status == LinkStatus.waiting);
      final s2 = AgentServer(
        identity: _identity,
        config: AgentServerConfig(port: port, address: InternetAddress.loopbackIPv4),
        devices: s.devices,
      );
      await s2.start();
      addTearDown(s2.dispose);
      link.reconnectNow();
      await _until(link, (st) => st.isConnected);
      expect(await link.request('agent.info'), containsPair('name', 'PC-Test'));
    });

    test('PegasusLink : révocation → état revoked, plus de tentatives', () async {
      final s = await _server();
      final a = await _pair(s);
      final link = PegasusLink();
      addTearDown(link.dispose);
      link.start(a);
      await _until(link, (st) => st.isConnected);
      await s.revoke(a.deviceId);
      final st = await _until(link, (st) => st.status == LinkStatus.revoked);
      expect(st.needsUserAction, isTrue);
    });

    test('PegasusLink : empreinte modifiée → untrusted', () async {
      final s = await _server();
      final a = await _pair(s);
      final link = PegasusLink();
      addTearDown(link.dispose);
      link.start(PairedAgent.fromJson({...a.toJson(), 'fingerprint': 'autre'}));
      expect((await _until(link, (st) => st.status == LinkStatus.untrusted)).needsUserAction, isTrue);
    });

    test('PegasusLink : PC éteint → waiting puis nouvelles tentatives', () async {
      final s = await _server();
      final a = await _pair(s);
      await s.stop();
      final link = PegasusLink(connectTimeout: const Duration(seconds: 1));
      addTearDown(link.dispose);
      link.start(a);
      final st = await _until(link, (st) => st.status == LinkStatus.waiting);
      expect(st.retryIn!.inMilliseconds, inInclusiveRange(800, 1200));
      expect(describeLinkError(st.error), isNotEmpty);
    });
  });
}
