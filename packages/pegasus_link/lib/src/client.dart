import 'dart:async';
import 'dart:io';

import 'package:pegasus_protocol/pegasus_protocol.dart';

/// L'empreinte du certificat présenté ne correspond pas à celle épinglée.
class FingerprintMismatchException implements Exception {
  const FingerprintMismatchException(this.expected, this.actual);
  final String expected;
  final String? actual;

  @override
  String toString() => 'Certificat inattendu (empreinte ${actual ?? '?'})';
}

/// Réponse en échec à une requête.
class RequestFailedException implements Exception {
  const RequestFailedException(this.op, this.error);
  final String op;
  final ProtocolError error;

  ErrorCode get code => error.code;

  @override
  String toString() => '$op : ${error.code.wire} ${error.message}';
}

/// La connexion a été fermée avant la réponse.
class ConnectionClosedException implements Exception {
  const ConnectionClosedException(this.closeCode, [this.reason]);
  final int? closeCode;
  final String? reason;

  @override
  String toString() => 'Connexion fermée ($closeCode${reason == null ? '' : ' $reason'})';
}

/// Description de l'appareil envoyée à l'appairage.
class DeviceDescriptor {
  const DeviceDescriptor({
    required this.id,
    required this.name,
    required this.platform,
    this.model = '',
  });
  final String id;
  final String name;
  final String platform;
  final String model;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'platform': platform, 'model': model};
}

/// Résultat d'un appairage réussi.
class PairingResult {
  const PairingResult({required this.agentId, required this.agentName, required this.deviceSecret});
  final String agentId;
  final String agentName;
  final String deviceSecret;
}

/// Informations reçues après `session.auth`.
class SessionInfo {
  const SessionInfo({
    required this.agentId,
    required this.agentName,
    required this.agentVersion,
    required this.os,
    required this.modules,
    required this.paused,
  });
  final String agentId;
  final String agentName;
  final String agentVersion;
  final String os;
  final Map<String, bool> modules;
  final bool paused;

  SessionInfo copyWith({Map<String, bool>? modules, bool? paused}) => SessionInfo(
        agentId: agentId,
        agentName: agentName,
        agentVersion: agentVersion,
        os: os,
        modules: modules ?? this.modules,
        paused: paused ?? this.paused,
      );

  static SessionInfo fromAuth(Map<String, Object?> data) {
    final agent = (data['agent'] as Map?)?.cast<String, Object?>() ?? const {};
    return SessionInfo(
      agentId: agent['id'] as String? ?? '',
      agentName: agent['name'] as String? ?? '',
      agentVersion: agent['version'] as String? ?? '',
      os: agent['os'] as String? ?? '',
      modules: parseModules(data['modules']),
      paused: data['paused'] == true,
    );
  }

  static Map<String, bool> parseModules(Object? raw) => {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is bool) e.key as String: e.value as bool,
      };
}

/// Ouverture des connexions TLS vers un agent, avec épinglage du certificat.
abstract final class PegasusClient {
  static const requestTimeout = Duration(seconds: 10);
  static const connectTimeout = Duration(seconds: 8);

  static Uri wsUri(String host, int port) =>
      Uri(scheme: 'wss', host: host, port: port, path: '/ws');

  /// Se connecte sans rien valider et renvoie l'empreinte du certificat
  /// présenté (appairage par code manuel : comparée à l'œil).
  static Future<String> probeFingerprint(String host, int port,
      {Duration timeout = connectTimeout}) async {
    String? seen;
    final http = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, _, _) {
        seen = PegasusCrypto.fingerprint(cert.der);
        return true;
      };
    try {
      final ws = await WebSocket.connect(wsUri(host, port).toString(), customClient: http)
          .timeout(timeout);
      await ws.close();
    } finally {
      http.close(force: true);
    }
    final fp = seen;
    if (fp == null) throw const HandshakeException('Certificat absent');
    return fp;
  }

  /// Ouvre une connexion vers l'agent dont le certificat a l'empreinte [fingerprint].
  static Future<PegasusConnection> connect({
    required String host,
    required int port,
    required String fingerprint,
    Duration timeout = connectTimeout,
  }) async {
    String? seen;
    final http = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, _, _) {
        seen = PegasusCrypto.fingerprint(cert.der);
        return PegasusCrypto.constantTimeEquals(seen!, fingerprint);
      };
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(wsUri(host, port).toString(), customClient: http)
          .timeout(timeout);
    } on HandshakeException {
      http.close(force: true);
      if (seen != null && seen != fingerprint) {
        throw FingerprintMismatchException(fingerprint, seen);
      }
      rethrow;
    } catch (_) {
      http.close(force: true);
      rethrow;
    }
    ws.pingInterval = const Duration(seconds: 15);
    return PegasusConnection._(ws, http);
  }
}

/// Connexion ouverte vers un agent.
class PegasusConnection {
  PegasusConnection._(this._ws, this._http) {
    _ws.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone(), cancelOnError: true);
  }

  final WebSocket _ws;
  final HttpClient _http;
  final _pending = <String, Completer<Map<String, Object?>>>{};
  final _pendingOps = <String, String>{};
  final _events = StreamController<Envelope>.broadcast();
  final _done = Completer<int?>();
  int _nextId = 1;

  /// Évènements `evt` poussés par l'agent.
  Stream<Envelope> get events => _events.stream;

  /// Complété à la fermeture, avec le code de fermeture.
  Future<int?> get done => _done.future;
  bool get isOpen => !_done.isCompleted;
  int? get closeCode => _ws.closeCode;

  /// Envoie une requête et attend la réponse (10 s max).
  Future<Map<String, Object?>> request(String op,
      [Map<String, Object?> data = const {}, Duration timeout = PegasusClient.requestTimeout]) {
    if (!isOpen) return Future.error(ConnectionClosedException(_ws.closeCode));
    final id = '${_nextId++}';
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _pendingOps[id] = op;
    _ws.add(Envelope.request(id, op, data).encode());
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      _pendingOps.remove(id);
      throw TimeoutException('$op sans réponse', timeout);
    });
  }

  /// Commande sans réponse (haute fréquence).
  void command(String op, [Map<String, Object?> data = const {}]) {
    if (isOpen) _ws.add(Envelope.command(op, data).encode());
  }

  /// Appairage par jeton (QR) ou code manuel (spec §3).
  Future<PairingResult> pair({String? token, String? code, required DeviceDescriptor device}) async {
    assert(token != null || code != null);
    final data = await request('pair.request', {
      'token': ?token,
      'code': ?code,
      'device': device.toJson(),
    });
    return PairingResult(
      agentId: data['agentId'] as String,
      agentName: data['agentName'] as String,
      deviceSecret: data['deviceSecret'] as String,
    );
  }

  /// Authentification (spec §4).
  Future<SessionInfo> authenticate({
    required String agentId,
    required String deviceId,
    required String deviceSecret,
    String appVersion = '0.1.0',
  }) async {
    final hello = await request('session.hello', {
      'deviceId': deviceId,
      'app': {'version': appVersion},
      'protocol': {'min': protocolVersion, 'max': protocolVersion},
    });
    final nonce = hello['nonce'] as String;
    final auth = await request('session.auth', {
      'mac': PegasusCrypto.authMac(
        deviceSecret: deviceSecret,
        nonce: nonce,
        agentId: agentId,
        deviceId: deviceId,
      ),
    });
    return SessionInfo.fromAuth(auth);
  }

  Future<void> close([int code = WebSocketStatus.normalClosure]) async {
    try {
      await _ws.close(code).timeout(const Duration(seconds: 2));
    } catch (_) {}
    _onDone();
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Envelope msg;
    try {
      msg = Envelope.decode(raw);
    } on FormatException {
      return;
    }
    switch (msg.type) {
      case MessageType.response:
        final completer = _pending.remove(msg.id);
        final op = _pendingOps.remove(msg.id) ?? '';
        if (completer == null) return;
        if (msg.ok == true) {
          completer.complete(msg.data);
        } else {
          completer.completeError(
              RequestFailedException(op, msg.error ?? const ProtocolError(ErrorCode.internal)));
        }
      case MessageType.event:
        _events.add(msg);
      case MessageType.request:
      case MessageType.command:
        break;
    }
  }

  void _onDone() {
    if (_done.isCompleted) return;
    final error = ConnectionClosedException(_ws.closeCode, _ws.closeReason);
    for (final c in _pending.values) {
      c.completeError(error);
    }
    _pending.clear();
    _pendingOps.clear();
    _done.complete(_ws.closeCode);
    _events.close();
    _http.close(force: true);
  }
}
