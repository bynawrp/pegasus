// Régressions remontées au test du paquet 1 :
// - coupure Wi-Fi silencieuse : le PC et l'app doivent le voir vite ;
// - « Oublier ce PC » doit retirer l'appareil de la liste du PC.
import 'dart:async';
import 'dart:io';

import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:test/test.dart';

final _identity = AgentIdentity.generate(name: 'PC-Test');
const _phone = DeviceDescriptor(id: 'tel', name: 'iPhone', platform: 'ios');

/// Proxy TCP qui peut « avaler » le trafic sans fermer les sockets,
/// comme un téléphone qui perd le Wi-Fi.
class BlackholeProxy {
  BlackholeProxy._(this._server, this.targetPort);
  final ServerSocket _server;
  final int targetPort;
  bool blackhole = false;
  final _sockets = <Socket>[];

  int get port => _server.port;

  static Future<BlackholeProxy> start(int targetPort) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = BlackholeProxy._(server, targetPort);
    server.listen(proxy._onClient);
    return proxy;
  }

  Future<void> _onClient(Socket client) async {
    final upstream = await Socket.connect(InternetAddress.loopbackIPv4, targetPort);
    _sockets.addAll([client, upstream]);
    client.listen((d) {
      if (!blackhole) upstream.add(d);
    }, onDone: upstream.destroy, onError: (_) => upstream.destroy());
    upstream.listen((d) {
      if (!blackhole) client.add(d);
    }, onDone: client.destroy, onError: (_) => client.destroy());
  }

  Future<void> close() async {
    for (final s in _sockets) {
      s.destroy();
    }
    await _server.close();
  }
}

Future<AgentServer> _server({Duration ping = const Duration(seconds: 5)}) async {
  final s = AgentServer(
    identity: _identity,
    config: AgentServerConfig(port: 0, address: InternetAddress.loopbackIPv4, pingInterval: ping),
  );
  await s.start();
  addTearDown(s.dispose);
  return s;
}

Future<PairedAgent> _pair(AgentServer s, {int? port}) async {
  final secret = s.pairing.renew();
  final c = await PegasusClient.connect(host: '127.0.0.1', port: s.port, fingerprint: _identity.fingerprint);
  final r = await c.pair(token: secret.token, device: _phone);
  await c.close();
  return PairedAgent(
    agentId: r.agentId,
    agentName: r.agentName,
    host: '127.0.0.1',
    port: port ?? s.port,
    fingerprint: _identity.fingerprint,
    deviceId: _phone.id,
    deviceSecret: r.deviceSecret,
  );
}

Future<LinkState> _until(PegasusLink link, bool Function(LinkState) test, [int seconds = 10]) async {
  if (test(link.state)) return link.state;
  return link.states.firstWhere(test).timeout(Duration(seconds: seconds));
}

void main() {
  test('ping par défaut : 5 s des deux côtés', () {
    expect(const AgentServerConfig().pingInterval, const Duration(seconds: 5));
    expect(PegasusClient.pingInterval, const Duration(seconds: 5));
  });

  test('coupure silencieuse → le PC voit l’appareil déconnecté en ~2 pings', () async {
    final s = await _server(ping: const Duration(milliseconds: 300));
    final proxy = await BlackholeProxy.start(s.port);
    addTearDown(proxy.close);
    final agent = await _pair(s, port: proxy.port);
    final link = PegasusLink(pingInterval: const Duration(seconds: 30));
    addTearDown(link.dispose);
    link.start(agent);
    await _until(link, (st) => st.isConnected);
    expect(s.sessions, hasLength(1));

    final disconnected = s.events.firstWhere((e) => e is DeviceDisconnected);
    final sw = Stopwatch()..start();
    proxy.blackhole = true;
    await disconnected.timeout(const Duration(seconds: 3));
    expect(sw.elapsedMilliseconds, lessThan(2000));
    expect(s.sessions, isEmpty);
  });

  test('coupure silencieuse → l’app passe en reconnexion en ~2 pings', () async {
    final s = await _server(ping: const Duration(seconds: 30));
    final proxy = await BlackholeProxy.start(s.port);
    addTearDown(proxy.close);
    final agent = await _pair(s, port: proxy.port);
    final link = PegasusLink(pingInterval: const Duration(milliseconds: 300));
    addTearDown(link.dispose);
    link.start(agent);
    await _until(link, (st) => st.isConnected);

    final sw = Stopwatch()..start();
    proxy.blackhole = true;
    await _until(link, (st) => !st.isConnected, 3);
    expect(sw.elapsedMilliseconds, lessThan(2000));

    // Réseau retrouvé : reconnexion immédiate, sans attendre le délai.
    proxy.blackhole = false;
    link.networkChanged();
    sw.reset();
    await _until(link, (st) => st.isConnected, 3);
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('networkChanged pendant une connexion active la remplace aussitôt', () async {
    final s = await _server();
    final agent = await _pair(s);
    final link = PegasusLink();
    addTearDown(link.dispose);
    link.start(agent);
    await _until(link, (st) => st.isConnected);
    link.networkChanged();
    await _until(link, (st) => st.status == LinkStatus.connecting, 2);
    await _until(link, (st) => st.isConnected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(s.sessions, hasLength(1));
  });

  test('networkChanged ne touche pas un état définitif (révoqué)', () async {
    final s = await _server();
    final agent = await _pair(s);
    final link = PegasusLink();
    addTearDown(link.dispose);
    link.start(agent);
    await _until(link, (st) => st.isConnected);
    await s.revoke(agent.deviceId);
    await _until(link, (st) => st.status == LinkStatus.revoked);
    link.networkChanged();
    expect(link.state.status, LinkStatus.revoked);
  });

  group('Oublier ce PC (session.unpair)', () {
    test('l’appareil est retiré de la liste du PC, évènement DeviceForgotten', () async {
      final s = await _server();
      final agent = await _pair(s);
      final events = <AgentServerEvent>[];
      s.events.listen(events.add);
      final link = PegasusLink();
      addTearDown(link.dispose);
      link.start(agent);
      await _until(link, (st) => st.isConnected);

      expect(await link.unpair(), isTrue);
      expect(link.state.status, LinkStatus.idle);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(s.devices, isEmpty);
      expect(s.sessions, isEmpty);
      expect(events.whereType<DeviceForgotten>().single.device.id, 'tel');
    });

    test('PC hors ligne → false, le lien est quand même arrêté', () async {
      final s = await _server();
      final agent = await _pair(s);
      await s.stop();
      final link = PegasusLink(connectTimeout: const Duration(seconds: 1));
      addTearDown(link.dispose);
      link.start(agent);
      await _until(link, (st) => st.status == LinkStatus.waiting);
      expect(await link.unpair(), isFalse);
      expect(link.state.status, LinkStatus.idle);
    });

    test('impossible sans authentification', () async {
      final s = await _server();
      await _pair(s);
      final c = await PegasusClient.connect(host: '127.0.0.1', port: s.port, fingerprint: _identity.fingerprint);
      addTearDown(c.close);
      await expectLater(
        c.request('session.unpair'),
        throwsA(isA<RequestFailedException>().having((e) => e.code, 'code', ErrorCode.unauthorized)),
      );
      expect(s.devices, hasLength(1));
    });

    test('fonctionne même agent en pause', () async {
      final s = await _server();
      final agent = await _pair(s);
      s.setPaused(true);
      final link = PegasusLink();
      addTearDown(link.dispose);
      link.start(agent);
      await _until(link, (st) => st.isConnected);
      expect(await link.unpair(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(s.devices, isEmpty);
    });
  });
}
