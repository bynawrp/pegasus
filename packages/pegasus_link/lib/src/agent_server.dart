import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:pegasus_protocol/pegasus_protocol.dart';

import 'devices.dart';
import 'identity.dart';
import 'network.dart';
import 'pairing_manager.dart';

/// Erreur métier levée par un gestionnaire d'opération : renvoyée telle quelle
/// au client dans une réponse en échec.
class OpException implements Exception {
  const OpException(this.code, [this.message = '']);
  final ErrorCode code;
  final String message;

  @override
  String toString() => 'OpException(${code.wire}, $message)';
}

typedef RequestHandler = FutureOr<Map<String, Object?>?> Function(
    AgentSession session, Map<String, Object?> data);
typedef CommandHandler = void Function(AgentSession session, Map<String, Object?> data);

class AgentServerConfig {
  const AgentServerConfig({
    this.port = defaultPort,
    this.address,
    this.agentVersion = '0.1.0',
    this.os = 'windows',
    this.handshakeTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 15),
    this.maxDevices = 5,
    this.maxPendingSockets = 16,
    this.commandsPerSecond = 200,
    this.requestsPerSecond = 20,
    this.isAllowedAddress = isLocalNetworkAddress,
  });

  final int port;

  /// Adresse d'écoute ; toutes les interfaces IPv4 par défaut.
  final InternetAddress? address;
  final String agentVersion;
  final String os;
  final Duration handshakeTimeout;
  final Duration pingInterval;
  final int maxDevices;
  final int maxPendingSockets;
  final int commandsPerSecond;
  final int requestsPerSecond;
  final bool Function(InternetAddress) isAllowedAddress;
}

/// Évènements observés par l'interface de l'agent.
sealed class AgentServerEvent {
  const AgentServerEvent();
}

class DevicePaired extends AgentServerEvent {
  const DevicePaired(this.device);
  final PairedDevice device;
}

class DeviceConnected extends AgentServerEvent {
  const DeviceConnected(this.device);
  final PairedDevice device;
}

class DeviceDisconnected extends AgentServerEvent {
  const DeviceDisconnected(this.device);
  final PairedDevice device;
}

class DevicesChanged extends AgentServerEvent {
  const DevicesChanged(this.devices);
  final List<PairedDevice> devices;
}

/// Une requête exécutée (journal, spec §9).
class RequestLogged extends AgentServerEvent {
  const RequestLogged({
    required this.time,
    required this.device,
    required this.op,
    required this.ok,
    this.module,
    this.error,
  });
  final DateTime time;
  final PairedDevice device;
  final String op;
  final String? module;
  final bool ok;
  final ErrorCode? error;
}

/// Serveur WebSocket TLS de l'agent (spec §1-§9).
class AgentServer {
  AgentServer({
    required this.identity,
    this.config = const AgentServerConfig(),
    Iterable<PairedDevice> devices = const [],
    PairingManager? pairing,
    Map<String, bool>? modules,
  })  : pairing = pairing ?? PairingManager(),
        _modules = {...?modules} {
    for (final d in devices) {
      _devices[d.id] = d;
    }
  }

  final AgentIdentity identity;
  final AgentServerConfig config;
  final PairingManager pairing;

  final Map<String, PairedDevice> _devices = {};
  final Map<String, bool> _modules;
  final Map<String, RequestHandler> _requests = {};
  final Map<String, CommandHandler> _commands = {};
  final Set<AgentSession> _sockets = {};
  final _events = StreamController<AgentServerEvent>.broadcast();

  HttpServer? _http;
  bool _paused = false;

  Stream<AgentServerEvent> get events => _events.stream;
  bool get isRunning => _http != null;
  int get port => _http?.port ?? config.port;
  bool get paused => _paused;
  Map<String, bool> get modules => UnmodifiableMapView(_modules);
  List<PairedDevice> get devices => List.unmodifiable(_devices.values);

  /// Sessions authentifiées.
  List<AgentSession> get sessions =>
      _sockets.where((s) => s.isAuthenticated).toList(growable: false);

  void onRequest(String op, RequestHandler handler) => _requests[op] = handler;
  void onCommand(String op, CommandHandler handler) => _commands[op] = handler;

  Future<void> start() async {
    if (_http != null) return;
    final http = await HttpServer.bindSecure(
      config.address ?? InternetAddress.anyIPv4,
      config.port,
      identity.securityContext(),
    );
    _http = http;
    http.listen(_handleHttp, onError: (_) {});
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    for (final s in _sockets.toList()) {
      await s.close(WebSocketStatus.goingAway, 'Agent arrêté');
    }
    await http?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await pairing.dispose();
  }

  /// Met l'agent en pause : seules `session.*` et `agent.*` répondent.
  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    broadcast(Envelope.event('session.paused', {'paused': value}));
  }

  void setModule(String module, bool enabled) {
    _modules[module] = enabled;
    broadcast(Envelope.event('session.modules', {'modules': Map.of(_modules)}));
  }

  bool isModuleEnabled(String module) => _modules[module] ?? true;

  /// Révoque un appareil : il est retiré et sa connexion fermée avec `4403`.
  Future<void> revoke(String deviceId) async {
    if (_devices.remove(deviceId) == null) return;
    _events.add(DevicesChanged(devices));
    for (final s in _sockets.where((s) => s.device?.id == deviceId).toList()) {
      await s.close(CloseCodes.revoked, 'Appareil révoqué');
    }
  }

  void renameDevice(String deviceId, String name) {
    final d = _devices[deviceId];
    if (d == null) return;
    _devices[deviceId] = d.copyWith(name: name);
    _events.add(DevicesChanged(devices));
  }

  /// Envoie un évènement à toutes les sessions authentifiées.
  void broadcast(Envelope event) {
    for (final s in sessions) {
      s.send(event);
    }
  }

  Map<String, Object?> agentInfo() => {
        'id': identity.agentId,
        'name': identity.name,
        'version': config.agentVersion,
        'os': config.os,
        'paused': _paused,
        'modules': _publicModules(),
      };

  Map<String, bool> _publicModules() => {
        for (final m in const ['input', 'media', 'power', 'apps']) m: isModuleEnabled(m),
        ..._modules,
      };

  Future<void> _handleHttp(HttpRequest request) async {
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null || !config.isAllowedAddress(remote)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (request.uri.path != '/ws' || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (_sockets.where((s) => !s.isAuthenticated).length >= config.maxPendingSockets) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }
    final WebSocket ws;
    try {
      ws = await WebSocketTransformer.upgrade(request);
    } catch (_) {
      return;
    }
    ws.pingInterval = config.pingInterval;
    final session = AgentSession._(this, ws, remote);
    _sockets.add(session);
    session._start();
  }

  void _sessionClosed(AgentSession session) {
    _sockets.remove(session);
    final device = session.device;
    if (session._stage == _Stage.authenticated && device != null) {
      _events.add(DeviceDisconnected(_devices[device.id] ?? device));
    }
  }

  void _authenticated(AgentSession session) {
    final device = session.device!;
    for (final other in sessions.where((s) => s != session && s.device?.id == device.id).toList()) {
      other.close(CloseCodes.replaced, 'Remplacée par une nouvelle connexion');
    }
    final updated = device.copyWith(lastSeen: DateTime.now());
    _devices[device.id] = updated;
    _events.add(DevicesChanged(devices));
    _events.add(DeviceConnected(updated));
  }

  PairedDevice _pair(Map<String, Object?> device) {
    final id = device['id'];
    final name = device['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const OpException(ErrorCode.badRequest, 'Appareil invalide');
    }
    final paired = PairedDevice(
      id: id,
      name: name.length > 64 ? name.substring(0, 64) : name,
      platform: device['platform'] as String? ?? '',
      model: device['model'] as String? ?? '',
      secret: PegasusCrypto.randomToken(32),
      pairedAt: DateTime.now(),
    );
    _devices[id] = paired;
    _events.add(DevicePaired(paired));
    _events.add(DevicesChanged(devices));
    return paired;
  }
}

enum _Stage { fresh, helloDone, authenticated }

/// Connexion d'un appareil à l'agent.
class AgentSession {
  AgentSession._(this._server, this._ws, this.remoteAddress);

  final AgentServer _server;
  final WebSocket _ws;
  final InternetAddress remoteAddress;

  _Stage _stage = _Stage.fresh;
  String? _nonce;
  String? _helloDeviceId;
  PairedDevice? _device;
  Timer? _handshakeTimer;
  bool _closed = false;
  final _cmdWindow = _RateWindow();
  final _reqWindow = _RateWindow();

  bool get isAuthenticated => _stage == _Stage.authenticated && !_closed;
  PairedDevice? get device => _device;

  void _start() {
    _handshakeTimer = Timer(_server.config.handshakeTimeout, () {
      if (_stage != _Stage.authenticated) {
        close(CloseCodes.handshakeTimeout, 'Handshake trop long');
      }
    });
    _ws.listen(
      _onMessage,
      onDone: _onDone,
      onError: (_) => _onDone(),
      cancelOnError: true,
    );
  }

  void send(Envelope envelope) {
    if (_closed) return;
    _ws.add(envelope.encode());
  }

  Future<void> close(int code, [String reason = '']) async {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    try {
      await _ws.close(code, reason).timeout(const Duration(seconds: 2));
    } catch (_) {}
    _server._sessionClosed(this);
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _server._sessionClosed(this);
  }

  Future<void> _onMessage(dynamic raw) async {
    if (_closed) return;
    if (raw is! String) {
      await close(CloseCodes.badHandshake, 'Trames texte uniquement');
      return;
    }
    if (raw.length > maxMessageBytes) {
      await close(WebSocketStatus.messageTooBig, 'Message trop grand');
      return;
    }
    final Envelope msg;
    try {
      msg = Envelope.decode(raw);
    } on FormatException {
      if (!isAuthenticated) await close(CloseCodes.badHandshake, 'Message invalide');
      return;
    }

    switch (msg.type) {
      case MessageType.command:
        _onCommand(msg);
      case MessageType.request:
        await _onRequest(msg);
      case MessageType.response:
      case MessageType.event:
        break; // Ignorés côté agent.
    }
  }

  void _onCommand(Envelope msg) {
    if (!isAuthenticated || _server.paused) return;
    if (!_cmdWindow.allow(_server.config.commandsPerSecond)) return;
    final op = msg.op!;
    final module = moduleForOp(op);
    if (module != null && !_server.isModuleEnabled(module)) return;
    final handler = _server._commands[op];
    if (handler == null) return;
    try {
      handler(this, msg.data);
    } catch (_) {}
  }

  Future<void> _onRequest(Envelope msg) async {
    final id = msg.id!;
    final op = msg.op!;

    if (!isAuthenticated) {
      switch (op) {
        case 'pair.request':
          return _onPair(msg);
        case 'session.hello':
          return _onHello(msg);
        case 'session.auth':
          return _onAuth(msg);
        default:
          send(Envelope.fail(id, ErrorCode.unauthorized, 'Session non authentifiée'));
          return;
      }
    }

    if (!_reqWindow.allow(_server.config.requestsPerSecond)) {
      send(Envelope.fail(id, ErrorCode.rateLimited, 'Trop de requêtes'));
      return;
    }

    if (op == 'agent.info') {
      send(Envelope.ok(id, _server.agentInfo()));
      return;
    }
    if (op.startsWith('session.') || op.startsWith('pair.')) {
      send(Envelope.fail(id, ErrorCode.badRequest, 'Session déjà authentifiée'));
      return;
    }

    final module = moduleForOp(op);
    if (_server.paused && module != null) {
      return _reply(msg, module, ErrorCode.paused, 'Agent en pause');
    }
    if (module != null && !_server.isModuleEnabled(module)) {
      return _reply(msg, module, ErrorCode.forbidden, 'Module « $module » désactivé sur ce PC');
    }
    final handler = _server._requests[op];
    if (handler == null) {
      send(Envelope.fail(id, ErrorCode.notSupported, 'Opération inconnue : $op'));
      return;
    }
    try {
      final result = await handler(this, msg.data);
      send(Envelope.ok(id, result ?? const {}));
      _log(op, module, true);
    } on OpException catch (e) {
      _reply(msg, module, e.code, e.message);
    } catch (e) {
      _reply(msg, module, ErrorCode.internal, 'Erreur interne');
    }
  }

  void _reply(Envelope msg, String? module, ErrorCode code, String message) {
    send(Envelope.fail(msg.id!, code, message));
    _log(msg.op!, module, false, code);
  }

  void _log(String op, String? module, bool ok, [ErrorCode? error]) {
    final device = _device;
    if (device == null) return;
    _server._events.add(RequestLogged(
      time: DateTime.now(),
      device: device,
      op: op,
      module: module,
      ok: ok,
      error: error,
    ));
  }

  void _onPair(Envelope msg) {
    final id = msg.id!;
    if (_stage != _Stage.fresh) {
      send(Envelope.fail(id, ErrorCode.badRequest, 'Appairage impossible à ce stade'));
      return;
    }
    final token = msg.data['token'];
    final code = msg.data['code'];
    final device = msg.data['device'];
    if ((token is! String && code is! String) || device is! Map<String, Object?>) {
      send(Envelope.fail(id, ErrorCode.badRequest, 'Jeton ou appareil manquant'));
      return;
    }
    final check = _server.pairing.consume(
      token: token is String ? token : null,
      code: code is String ? code : null,
    );
    switch (check) {
      case PairingCheck.ok:
        try {
          final paired = _server._pair(device);
          send(Envelope.ok(id, {
            'agentId': _server.identity.agentId,
            'agentName': _server.identity.name,
            'deviceSecret': paired.secret,
          }));
        } on OpException catch (e) {
          send(Envelope.fail(id, e.code, e.message));
        }
      case PairingCheck.expired:
        send(Envelope.fail(id, ErrorCode.rejected, 'Code expiré, générez-en un nouveau'));
      case PairingCheck.locked:
        send(Envelope.fail(id, ErrorCode.rejected, 'Trop d’essais, générez un nouveau code'));
      case PairingCheck.invalid:
        send(Envelope.fail(id, ErrorCode.rejected, 'Code invalide'));
    }
  }

  Future<void> _onHello(Envelope msg) async {
    final id = msg.id!;
    if (_stage != _Stage.fresh) {
      await close(CloseCodes.badHandshake, 'session.hello en double');
      return;
    }
    final deviceId = msg.data['deviceId'];
    final protocol = msg.data['protocol'];
    if (deviceId is! String || protocol is! Map<String, Object?>) {
      await close(CloseCodes.badHandshake, 'session.hello invalide');
      return;
    }
    final min = protocol['min'];
    final max = protocol['max'];
    if (min is! int || max is! int || min > protocolVersion || max < protocolVersion) {
      await close(CloseCodes.unsupportedVersion, 'Version de protocole non supportée');
      return;
    }
    if (!_server._devices.containsKey(deviceId)) {
      await close(CloseCodes.revoked, 'Appareil inconnu ou révoqué');
      return;
    }
    _helloDeviceId = deviceId;
    _nonce = PegasusCrypto.randomToken(32);
    _stage = _Stage.helloDone;
    send(Envelope.ok(id, {'nonce': _nonce, 'protocol': protocolVersion}));
  }

  Future<void> _onAuth(Envelope msg) async {
    final id = msg.id!;
    final nonce = _nonce;
    final deviceId = _helloDeviceId;
    _nonce = null; // Usage unique.
    if (_stage != _Stage.helloDone || nonce == null || deviceId == null) {
      await close(CloseCodes.badHandshake, 'session.auth sans session.hello');
      return;
    }
    final device = _server._devices[deviceId];
    if (device == null) {
      await close(CloseCodes.revoked, 'Appareil révoqué');
      return;
    }
    final mac = msg.data['mac'];
    final expected = PegasusCrypto.authMac(
      deviceSecret: device.secret,
      nonce: nonce,
      agentId: _server.identity.agentId,
      deviceId: deviceId,
    );
    if (mac is! String || !PegasusCrypto.constantTimeEquals(mac, expected)) {
      await close(CloseCodes.unauthorized, 'Authentification refusée');
      return;
    }
    final others = _server.sessions.where((s) => s.device?.id != deviceId).length;
    if (others >= _server.config.maxDevices) {
      send(Envelope.fail(id, ErrorCode.rateLimited, 'Trop d’appareils connectés'));
      await close(CloseCodes.unauthorized, 'Trop d’appareils connectés');
      return;
    }
    _handshakeTimer?.cancel();
    _device = device;
    _stage = _Stage.authenticated;
    _server._authenticated(this);
    final info = _server.agentInfo();
    send(Envelope.ok(id, {
      'agent': {
        'id': info['id'],
        'name': info['name'],
        'version': info['version'],
        'os': info['os'],
      },
      'modules': info['modules'],
      'paused': info['paused'],
    }));
  }
}

/// Compteur glissant sur une seconde.
class _RateWindow {
  final _times = Queue<int>();

  bool allow(int perSecond) {
    final now = DateTime.now().microsecondsSinceEpoch;
    while (_times.isNotEmpty && now - _times.first >= 1000000) {
      _times.removeFirst();
    }
    if (_times.length >= perSecond) return false;
    _times.add(now);
    return true;
  }
}
