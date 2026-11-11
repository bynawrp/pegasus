import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import 'providers.dart';

/// Échec d'appairage, avec un message pour l'utilisateur.
class PairingFailure implements Exception {
  const PairingFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

final pairingServiceProvider = Provider<PairingService>(PairingService.new);

/// Appairage avec un PC (spec §3) : par QR code ou par code manuel.
class PairingService {
  PairingService(this._ref);
  final Ref _ref;

  /// Appairage à partir du contenu du QR code.
  Future<PairedAgent> pairWithQr(String raw) async {
    final PairingInvite invite;
    try {
      invite = PairingInvite.parse(raw);
    } on FormatException catch (e) {
      throw PairingFailure(e.message);
    }
    if (invite.version != protocolVersion) {
      throw const PairingFailure('Version de Pegasus incompatible : mettez à jour l’app ou le PC');
    }
    return _pair(
      host: invite.host,
      port: invite.port,
      fingerprint: invite.fingerprint,
      token: invite.token,
    );
  }

  /// Première étape du code manuel : empreinte présentée par le PC, que
  /// l'utilisateur compare à celle affichée par l'agent.
  Future<String> probe(String host, int port) async {
    try {
      return await PegasusClient.probeFingerprint(host.trim(), port);
    } catch (e) {
      throw PairingFailure(_networkMessage(e));
    }
  }

  /// Seconde étape du code manuel, une fois l'empreinte confirmée.
  Future<PairedAgent> pairWithCode({
    required String host,
    required int port,
    required String fingerprint,
    required String code,
  }) =>
      _pair(host: host.trim(), port: port, fingerprint: fingerprint, code: code.replaceAll(' ', ''));

  Future<PairedAgent> _pair({
    required String host,
    required int port,
    required String fingerprint,
    String? token,
    String? code,
  }) async {
    final device = await _ref.read(deviceDescriptorProvider.future);
    PegasusConnection? conn;
    try {
      conn = await PegasusClient.connect(host: host, port: port, fingerprint: fingerprint);
      final result = await conn.pair(token: token, code: code, device: device);
      final pc = PairedAgent(
        agentId: result.agentId,
        agentName: result.agentName,
        host: host,
        port: port,
        fingerprint: fingerprint,
        deviceId: device.id,
        deviceSecret: result.deviceSecret,
      );
      await _ref.read(pairedPcProvider.notifier).save(pc);
      _ref.read(pairingNoticeProvider.notifier).show(null);
      return pc;
    } on RequestFailedException catch (e) {
      throw PairingFailure(e.error.message.isEmpty ? 'Appairage refusé' : e.error.message);
    } on FingerprintMismatchException {
      throw const PairingFailure('Le certificat du PC ne correspond pas : appairage annulé');
    } catch (e) {
      throw PairingFailure(_networkMessage(e));
    } finally {
      await conn?.close();
    }
  }

  static String _networkMessage(Object e) => switch (e) {
        PairingFailure(:final message) => message,
        SocketException() => 'PC injoignable : vérifiez l’adresse et que le téléphone est sur le même Wi-Fi',
        TimeoutException() => 'Le PC ne répond pas',
        HandshakeException() => 'Connexion sécurisée impossible',
        _ => 'Erreur de connexion',
      };
}
