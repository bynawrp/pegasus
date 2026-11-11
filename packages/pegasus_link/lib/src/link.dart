import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:pegasus_protocol/pegasus_protocol.dart';

import 'client.dart';

/// PC associé, tel que mémorisé par l'app (secret compris).
class PairedAgent {
  const PairedAgent({
    required this.agentId,
    required this.agentName,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.deviceId,
    required this.deviceSecret,
  });

  final String agentId;
  final String agentName;
  final String host;
  final int port;
  final String fingerprint;
  final String deviceId;
  final String deviceSecret;

  PairedAgent copyWith({String? agentName, String? host, int? port}) => PairedAgent(
        agentId: agentId,
        agentName: agentName ?? this.agentName,
        host: host ?? this.host,
        port: port ?? this.port,
        fingerprint: fingerprint,
        deviceId: deviceId,
        deviceSecret: deviceSecret,
      );

  Map<String, Object?> toJson() => {
        'agentId': agentId,
        'agentName': agentName,
        'host': host,
        'port': port,
        'fingerprint': fingerprint,
        'deviceId': deviceId,
        'deviceSecret': deviceSecret,
      };

  factory PairedAgent.fromJson(Map<String, Object?> json) => PairedAgent(
        agentId: json['agentId'] as String,
        agentName: json['agentName'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        fingerprint: json['fingerprint'] as String,
        deviceId: json['deviceId'] as String,
        deviceSecret: json['deviceSecret'] as String,
      );
}

/// Délai avant la tentative de reconnexion n° [attempt] (0 = première) :
/// 1 s, 2, 4, 8, 16 puis 30 s max, ±20 % d'aléa (spec §5).
Duration reconnectDelay(int attempt, [Random? random]) {
  final base = attempt >= 5 ? 30.0 : min(30.0, pow(2, attempt).toDouble());
  final jitter = 1 + ((random ?? Random()).nextDouble() * 0.4 - 0.2);
  return Duration(milliseconds: (base * 1000 * jitter).round());
}

enum LinkStatus {
  /// Pas de connexion demandée.
  idle,
  connecting,
  connected,

  /// En attente avant une nouvelle tentative.
  waiting,

  /// Appareil révoqué par le PC (4403) : il faut réassocier.
  revoked,

  /// Secret refusé (4401) : il faut réassocier.
  unauthorized,

  /// Certificat différent de celui épinglé : connexion refusée.
  untrusted,

  /// Une autre connexion du même appareil a pris la place (4409).
  replaced,
}

class LinkState {
  const LinkState(this.status, {this.info, this.retryIn, this.error, this.attempt = 0});

  final LinkStatus status;
  final SessionInfo? info;
  final Duration? retryIn;
  final Object? error;
  final int attempt;

  bool get isConnected => status == LinkStatus.connected;

  /// États définitifs : pas de reconnexion automatique.
  bool get needsUserAction => const {
        LinkStatus.revoked,
        LinkStatus.unauthorized,
        LinkStatus.untrusted,
      }.contains(status);

  @override
  String toString() => 'LinkState($status, attempt: $attempt, error: $error)';
}

/// Maintient la connexion authentifiée vers un PC associé, avec
/// reconnexion automatique (spec §5).
class PegasusLink {
  PegasusLink({
    this.appVersion = '0.1.0',
    Random? random,
    this.connectTimeout = PegasusClient.connectTimeout,
    this.pingInterval = PegasusClient.pingInterval,
  }) : _random = random ?? Random();

  final String appVersion;
  final Duration connectTimeout;
  final Duration pingInterval;
  final Random _random;
  final _states = StreamController<LinkState>.broadcast();
  final _events = StreamController<Envelope>.broadcast();

  LinkState _state = const LinkState(LinkStatus.idle);
  PairedAgent? _agent;
  PegasusConnection? _connection;
  Timer? _retryTimer;
  int _attempt = 0;
  int _generation = 0;

  LinkState get state => _state;
  Stream<LinkState> get states => _states.stream;

  /// Évènements de l'agent (hors évènements de session déjà gérés ici).
  Stream<Envelope> get events => _events.stream;
  PegasusConnection? get connection => _state.isConnected ? _connection : null;
  PairedAgent? get agent => _agent;

  /// Démarre (ou redémarre) la connexion vers [agent].
  void start(PairedAgent agent) {
    _agent = agent;
    _attempt = 0;
    _connect();
  }

  /// Arrête la connexion et toute reconnexion.
  Future<void> stop() async {
    _generation++;
    _retryTimer?.cancel();
    _agent = null;
    final c = _connection;
    _connection = null;
    _set(const LinkState(LinkStatus.idle));
    await c?.close();
  }

  /// Retente immédiatement (retour de l'app au premier plan).
  void reconnectNow() {
    if (_agent == null) return;
    if (_state.status == LinkStatus.waiting || _state.status == LinkStatus.replaced) {
      _attempt = 0;
      _connect();
    }
  }

  /// Le réseau du téléphone a changé (Wi-Fi coupé / retrouvé) : la connexion
  /// en cours est probablement morte, on la remplace tout de suite.
  void networkChanged() {
    if (_agent == null || _state.needsUserAction) return;
    if (_state.status == LinkStatus.connecting) return;
    _attempt = 0;
    _connect();
  }

  /// Demande au PC d'oublier cet appareil puis arrête le lien.
  /// Renvoie `false` si le PC n'a pas pu être prévenu (hors ligne).
  Future<bool> unpair() async {
    final c = connection;
    var notified = false;
    if (c != null) {
      _generation++; // La fermeture qui suit ne déclenche pas de reconnexion.
      try {
        await c.unpair();
        notified = true;
      } catch (_) {}
    }
    await stop();
    return notified;
  }

  Future<Map<String, Object?>> request(String op, [Map<String, Object?> data = const {}]) {
    final c = connection;
    if (c == null) return Future.error(const ConnectionClosedException(null, 'Non connecté'));
    return c.request(op, data);
  }

  void command(String op, [Map<String, Object?> data = const {}]) => connection?.command(op, data);

  Future<void> dispose() async {
    await stop();
    await _states.close();
    await _events.close();
  }

  Future<void> _connect() async {
    final agent = _agent;
    if (agent == null) return;
    final gen = ++_generation;
    _retryTimer?.cancel();
    final old = _connection;
    _connection = null;
    unawaited(old?.close());
    _set(LinkState(LinkStatus.connecting, attempt: _attempt));

    PegasusConnection? conn;
    try {
      conn = await PegasusClient.connect(
        host: agent.host,
        port: agent.port,
        fingerprint: agent.fingerprint,
        timeout: connectTimeout,
        ping: pingInterval,
      );
      if (gen != _generation) {
        unawaited(conn.close());
        return;
      }
      final info = await conn.authenticate(
        agentId: agent.agentId,
        deviceId: agent.deviceId,
        deviceSecret: agent.deviceSecret,
        appVersion: appVersion,
      );
      if (gen != _generation) {
        unawaited(conn.close());
        return;
      }
      _connection = conn;
      _attempt = 0;
      _set(LinkState(LinkStatus.connected, info: info));
      final c = conn;
      c.events.listen(_onEvent);
      unawaited(c.done.then((code) => _onClosed(gen, code)));
    } on FingerprintMismatchException catch (e) {
      if (gen != _generation) return;
      _set(LinkState(LinkStatus.untrusted, error: e));
    } catch (e) {
      if (gen != _generation) return;
      final code = conn?.closeCode ?? (e is ConnectionClosedException ? e.closeCode : null);
      if (!_terminal(code, e)) _scheduleRetry(e);
    }
  }

  void _onEvent(Envelope evt) {
    final info = _state.info;
    if (evt.op == 'session.paused' && info != null) {
      _set(LinkState(LinkStatus.connected, info: info.copyWith(paused: evt.data['paused'] == true)));
    } else if (evt.op == 'session.modules' && info != null) {
      _set(LinkState(LinkStatus.connected,
          info: info.copyWith(modules: SessionInfo.parseModules(evt.data['modules']))));
    }
    if (!_events.isClosed) _events.add(evt);
  }

  void _onClosed(int gen, int? code) {
    if (gen != _generation) return;
    _connection = null;
    if (_terminal(code, null)) return;
    _scheduleRetry(ConnectionClosedException(code));
  }

  /// Gère les codes de fermeture qui interdisent de réessayer.
  bool _terminal(int? code, Object? error) {
    final status = switch (code) {
      CloseCodes.revoked => LinkStatus.revoked,
      CloseCodes.unauthorized => LinkStatus.unauthorized,
      CloseCodes.replaced => LinkStatus.replaced,
      _ => null,
    };
    if (status == null) return false;
    _set(LinkState(status, error: error));
    return true;
  }

  void _scheduleRetry(Object error) {
    if (_agent == null) return;
    final delay = reconnectDelay(_attempt, _random);
    _set(LinkState(LinkStatus.waiting, retryIn: delay, error: error, attempt: _attempt));
    _attempt++;
    final gen = _generation;
    _retryTimer = Timer(delay, () {
      if (gen == _generation) _connect();
    });
  }

  void _set(LinkState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}

/// Erreur lisible pour l'utilisateur.
String describeLinkError(Object? error) => switch (error) {
      null => '',
      FingerprintMismatchException() => 'Certificat du PC inattendu',
      SocketException() => 'PC injoignable',
      HandshakeException() => 'Échec de la connexion sécurisée',
      TimeoutException() => 'Le PC ne répond pas',
      ConnectionClosedException() => 'Connexion perdue',
      RequestFailedException(:final error) => error.message,
      _ => 'Erreur de connexion',
    };
