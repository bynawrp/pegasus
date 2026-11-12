import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import '../modules/input/input_module.dart';
import '../platform/input_controller.dart';
import 'agent_store.dart';

const agentVersion = '0.1.0';

enum AgentStatus { starting, running, error }

/// Ligne de l'activité récente (accueil).
class ActivityEntry {
  const ActivityEntry(this.time, this.label, {this.ok = true});
  final DateTime time;
  final String label;
  final bool ok;
}

/// État affiché par l'interface de l'agent.
class AgentViewState {
  const AgentViewState({
    this.status = AgentStatus.starting,
    this.error,
    this.agentName = '',
    this.agentId = '',
    this.fingerprint = '',
    this.port = defaultPort,
    this.addresses = const [],
    this.paused = false,
    this.pairing,
    this.pairingLocked = false,
    this.devices = const [],
    this.connected = const {},
    this.activity = const [],
  });

  final AgentStatus status;
  final String? error;
  final String agentName;
  final String agentId;
  final String fingerprint;
  final int port;

  /// Adresses IPv4 locales, la plus probable en premier.
  final List<String> addresses;
  final bool paused;
  final PairingSecret? pairing;
  final bool pairingLocked;
  final List<PairedDevice> devices;

  /// Identifiants des appareils actuellement connectés.
  final Set<String> connected;

  /// Plus récent en premier.
  final List<ActivityEntry> activity;

  String? get primaryAddress => addresses.isEmpty ? null : addresses.first;

  /// Contenu du QR code, s'il y a un jeton valide et une adresse.
  PairingInvite? get invite {
    final p = pairing;
    final host = primaryAddress;
    if (p == null || host == null || status != AgentStatus.running) return null;
    if (!DateTime.now().isBefore(p.expiresAt)) return null;
    return PairingInvite(
      host: host,
      port: port,
      agentId: agentId,
      agentName: agentName,
      fingerprint: fingerprint,
      token: p.token,
    );
  }

  AgentViewState copyWith({
    AgentStatus? status,
    String? error,
    String? agentName,
    String? agentId,
    String? fingerprint,
    int? port,
    List<String>? addresses,
    bool? paused,
    PairingSecret? Function()? pairing,
    bool? pairingLocked,
    List<PairedDevice>? devices,
    Set<String>? connected,
    List<ActivityEntry>? activity,
  }) =>
      AgentViewState(
        status: status ?? this.status,
        error: error ?? this.error,
        agentName: agentName ?? this.agentName,
        agentId: agentId ?? this.agentId,
        fingerprint: fingerprint ?? this.fingerprint,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
        paused: paused ?? this.paused,
        pairing: pairing != null ? pairing() : this.pairing,
        pairingLocked: pairingLocked ?? this.pairingLocked,
        devices: devices ?? this.devices,
        connected: connected ?? this.connected,
        activity: activity ?? this.activity,
      );
}

/// Dossier des données de l'agent (remplaçable dans les tests).
final agentDirectoryProvider = FutureProvider<Directory>((ref) => getApplicationSupportDirectory());

/// Souris / clavier du PC (remplacé par un enregistreur dans les tests).
final inputControllerProvider = Provider<InputController?>((ref) => InputController.platform());

/// Configuration réseau du serveur (remplaçable dans les tests).
final agentServerConfigProvider = Provider<AgentServerConfig>(
  (ref) => const AgentServerConfig(agentVersion: agentVersion),
);

final agentControllerProvider =
    NotifierProvider<AgentController, AgentViewState>(AgentController.new);

/// Démarre le serveur de l'agent et expose son état à l'interface.
class AgentController extends Notifier<AgentViewState> {
  AgentServer? _server;
  AgentStore? _store;
  StreamSubscription<AgentServerEvent>? _events;
  StreamSubscription<PairingSecret?>? _pairingChanges;
  final _names = <String, String>{};
  Future<void> _saving = Future.value();
  bool _disposed = false;

  static const _maxActivity = 30;

  @override
  AgentViewState build() {
    ref.onDispose(() {
      _disposed = true;
      _events?.cancel();
      _pairingChanges?.cancel();
      _server?.dispose();
    });
    Future.microtask(_start);
    return const AgentViewState();
  }

  AgentServer? get server => _server;

  Future<void> _start() async {
    final port = ref.read(agentServerConfigProvider).port;
    try {
      final dir = await ref.read(agentDirectoryProvider.future);
      if (_disposed) return;
      final store = AgentStore(dir);
      final data = await store.loadOrCreate(defaultName: Platform.localHostname);
      if (_disposed) return;
      final server = AgentServer(
        identity: data.identity,
        devices: data.devices,
        config: ref.read(agentServerConfigProvider),
      );
      _store = store;
      _server = server;
      final input = ref.read(inputControllerProvider);
      if (input != null) {
        registerInputModule(server, input);
      } else {
        server.setModule('input', false);
      }
      _events = server.events.listen(_onEvent);
      _pairingChanges = server.pairing.changes.listen(_onPairingChanged);
      state = state.copyWith(
        agentName: data.identity.name,
        agentId: data.identity.agentId,
        fingerprint: data.identity.fingerprint,
        devices: server.devices,
      );
      await server.start();
      final addresses = await localIPv4Addresses();
      if (_disposed) {
        await server.dispose();
        return;
      }
      state = state.copyWith(status: AgentStatus.running, addresses: addresses, port: server.port);
      server.pairing.renew();
    } on SocketException catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        status: AgentStatus.error,
        error: 'Impossible d’écouter sur le port $port (${e.osError?.message ?? e.message})',
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(status: AgentStatus.error, error: 'Démarrage impossible : $e');
    }
  }


  /// Nouveau QR code et nouveau code manuel.
  void renewPairing() {
    final s = _server;
    if (s == null) return;
    s.pairing.renew();
  }

  void setPaused(bool paused) {
    _server?.setPaused(paused);
    _addActivity(paused ? 'Contrôle mis en pause' : 'Contrôle repris',
        base: state.copyWith(paused: paused));
  }

  Future<void> revoke(String deviceId) async {
    final name = _deviceName(deviceId);
    await _server?.revoke(deviceId);
    _addActivity('$name révoqué');
  }

  void rename(String deviceId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _server?.renameDevice(deviceId, trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed);
  }

  /// Rafraîchit les adresses réseau (changement de Wi-Fi).
  Future<void> refreshAddresses() async {
    state = state.copyWith(addresses: await localIPv4Addresses());
  }

  String _deviceName(String id) =>
      _names[id] ?? state.devices.where((d) => d.id == id).firstOrNull?.name ?? 'Appareil';

  void _onEvent(AgentServerEvent event) {
    final server = _server;
    if (_disposed || server == null) return;
    switch (event) {
      case DevicesChanged(:final devices):
        for (final d in devices) {
          _names[d.id] = d.name;
        }
        state = state.copyWith(devices: devices);
        _persist();
      case DeviceForgotten(:final device):
        _addActivity('${device.name} a oublié ce PC');
      case DevicePaired(:final device):
        _addActivity('${device.name} associé');
      case DeviceConnected(:final device):
        _addActivity('${device.name} connecté',
            base: state.copyWith(connected: {...state.connected, device.id}));
      case DeviceDisconnected(:final device):
        final still = server.sessions.any((s) => s.device?.id == device.id);
        if (!still && state.connected.contains(device.id)) {
          _addActivity('${device.name} déconnecté',
              base: state.copyWith(connected: {...state.connected}..remove(device.id)));
        }
      case RequestLogged(:final device, :final op, :final ok):
        _addActivity('${device.name} · $op', ok: ok);
    }
  }

  void _onPairingChanged(PairingSecret? _) {
    final s = _server;
    if (_disposed || s == null) return;
    state = state.copyWith(pairing: () => s.pairing.current, pairingLocked: s.pairing.locked);
  }

  /// Ajoute une ligne d'activité, en une seule mise à jour avec [base].
  void _addActivity(String label, {bool ok = true, AgentViewState? base}) {
    final b = base ?? state;
    final list = [ActivityEntry(DateTime.now(), label, ok: ok), ...b.activity];
    state = b.copyWith(activity: list.take(_maxActivity).toList());
  }

  /// Sauvegardes sérialisées : une écriture à la fois, toujours la dernière liste.
  Future<void> _persist() {
    final server = _server;
    final store = _store;
    if (server == null || store == null) return _saving;
    return _saving = _saving.then((_) async {
      if (_disposed) return;
      try {
        await store.save(AgentData(identity: server.identity, devices: server.devices));
      } catch (_) {
        // Disque indisponible : la prochaine modification retentera.
      }
    });
  }

  /// Attend la fin des sauvegardes en cours (tests, arrêt).
  Future<void> flush() => _saving;
}
