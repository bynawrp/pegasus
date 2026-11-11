// Parcours complets de l'app contre un vrai serveur d'agent (TLS, loopback).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/core/pairing_service.dart';
import 'package:pegasus/src/core/providers.dart';
import 'package:pegasus/src/core/secure_store.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

final _identity = AgentIdentity.generate(name: 'PC-Bureau');

Future<AgentServer> _agent() async {
  final server = AgentServer(
    identity: _identity,
    config: AgentServerConfig(port: 0, address: InternetAddress.loopbackIPv4),
  );
  await server.start();
  addTearDown(server.dispose);
  return server;
}

PairingInvite _invite(AgentServer s) => PairingInvite(
      host: '127.0.0.1',
      port: s.port,
      agentId: _identity.agentId,
      agentName: _identity.name,
      fingerprint: _identity.fingerprint,
      token: s.pairing.renew().token,
    );

Future<T> _until<T>(ProviderContainer c, ProviderListenable<T> p, bool Function(T) test) async {
  if (test(c.read(p))) return c.read(p);
  final completer = Completer<T>();
  final sub = c.listen<T>(p, (_, next) {
    if (test(next) && !completer.isCompleted) completer.complete(next);
  });
  try {
    return await completer.future.timeout(const Duration(seconds: 10));
  } finally {
    sub.close();
  }
}

Matcher _failure(String text) =>
    throwsA(isA<PairingFailure>().having((e) => e.message, 'message', contains(text)));

void main() {
  late MemorySecureStore store;
  late ProviderContainer container;

  setUp(() {
    store = MemorySecureStore();
    container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(store),
      deviceNameProvider.overrideWith((ref) async => 'Pixel Test'),
    ]);
    addTearDown(container.dispose);
    container.read(linkStateProvider);
  });

  PairingService service() => container.read(pairingServiceProvider);

  test('QR → associé, secret stocké, connecté automatiquement', () async {
    final agent = await _agent();
    final pc = await service().pairWithQr(_invite(agent).toString());
    expect(pc.agentName, 'PC-Bureau');
    final saved = jsonDecode(store.values['pc.current']!) as Map;
    expect(saved['deviceSecret'], pc.deviceSecret);
    expect(store.values['device.id'], pc.deviceId);
    expect(agent.devices.single.name, 'Pixel Test');
    final link = await _until(container, linkStateProvider, (s) => s.isConnected);
    expect(link.info!.agentName, 'PC-Bureau');
  });

  test('le même identifiant d’appareil est réutilisé', () async {
    final agent = await _agent();
    final first = await service().pairWithQr(_invite(agent).toString());
    final second = await service().pairWithQr(_invite(agent).toString());
    expect(second.deviceId, first.deviceId);
    expect(agent.devices, hasLength(1));
  });

  test('QR étranger → message clair', () async {
    expect(service().pairWithQr('https://exemple.fr'), _failure('pas un code Pegasus'));
  });

  test('QR déjà utilisé → refus de l’agent', () async {
    final agent = await _agent();
    final invite = _invite(agent).toString();
    await service().pairWithQr(invite);
    expect(service().pairWithQr(invite), _failure('Code'));
  });

  test('QR avec une empreinte falsifiée → refus', () async {
    final agent = await _agent();
    final invite = _invite(agent);
    final forged = PairingInvite(
      host: invite.host,
      port: invite.port,
      agentId: invite.agentId,
      agentName: invite.agentName,
      fingerprint: PegasusCrypto.randomToken(),
      token: invite.token,
    );
    await expectLater(service().pairWithQr(forged.toString()), _failure('certificat'));
    expect(agent.devices, isEmpty);
  });

  test('code manuel : empreinte sondée puis appairage', () async {
    final agent = await _agent();
    final code = agent.pairing.renew().code;
    final fp = await service().probe('127.0.0.1', agent.port);
    expect(fp, _identity.fingerprint);
    await service().pairWithCode(host: ' 127.0.0.1 ', port: agent.port, fingerprint: fp, code: code);
    await _until(container, linkStateProvider, (s) => s.isConnected);
  });

  test('code manuel faux → « Code invalide »', () async {
    final agent = await _agent();
    agent.pairing.renew();
    expect(
      service().pairWithCode(host: '127.0.0.1', port: agent.port, fingerprint: _identity.fingerprint, code: '000000'),
      _failure('Code invalide'),
    );
  });

  test('PC injoignable → message réseau', () async {
    final agent = await _agent();
    final port = agent.port;
    await agent.stop();
    expect(service().probe('127.0.0.1', port), _failure('injoignable'));
  });

  test('révocation par le PC → secret supprimé, message affiché', () async {
    final agent = await _agent();
    final pc = await service().pairWithQr(_invite(agent).toString());
    await _until(container, linkStateProvider, (s) => s.isConnected);
    await agent.revoke(pc.deviceId);
    await _until(container, pairedPcProvider, (v) => v is AsyncData && v.value == null);
    expect(store.values.containsKey('pc.current'), isFalse);
    expect(container.read(pairingNoticeProvider), contains('révoqué'));
  });

  test('oublier le PC → déconnecté, secret supprimé', () async {
    final agent = await _agent();
    await service().pairWithQr(_invite(agent).toString());
    await _until(container, linkStateProvider, (s) => s.isConnected);
    await container.read(pairedPcProvider.notifier).forget();
    await _until(container, linkStateProvider, (s) => s.status == LinkStatus.idle);
    expect(store.values.containsKey('pc.current'), isFalse);
    for (var i = 0; i < 50 && agent.sessions.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(agent.sessions, isEmpty);
  });

  test('relance de l’app → reconnexion avec le PC mémorisé', () async {
    final agent = await _agent();
    await service().pairWithQr(_invite(agent).toString());
    final c2 = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(store),
      deviceNameProvider.overrideWith((ref) async => 'Pixel Test'),
    ]);
    addTearDown(c2.dispose);
    c2.read(linkStateProvider);
    final s = await _until(c2, linkStateProvider, (s) => s.isConnected);
    expect(s.info!.agentName, 'PC-Bureau');
  });

  test('pause sur le PC → état reflété dans l’app', () async {
    final agent = await _agent();
    await service().pairWithQr(_invite(agent).toString());
    await _until(container, linkStateProvider, (s) => s.isConnected);
    agent.setPaused(true);
    await _until(container, linkStateProvider, (s) => s.info?.paused == true);
  });
}
