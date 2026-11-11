import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';

import 'secure_store.dart';

const appVersion = '0.1.0';

/// Stockage sécurisé (remplacé par [MemorySecureStore] dans les tests).
final secureStoreProvider = Provider<SecureStore>((ref) => const FlutterSecureStore());

/// Nom affiché de ce téléphone sur le PC (remplaçable dans les tests).
final deviceNameProvider = FutureProvider<String>((ref) async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      final brand = a.manufacturer.isEmpty
          ? ''
          : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
      return '$brand${a.model}'.trim();
    }
    if (Platform.isIOS) return (await info.iosInfo).name;
  } catch (_) {}
  return 'Mon téléphone';
});

/// Identité de ce téléphone (UUID stable + nom + plateforme).
final deviceDescriptorProvider = FutureProvider<DeviceDescriptor>((ref) async {
  final store = ref.read(secureStoreProvider);
  var id = await store.read(_deviceIdKey);
  if (id == null) {
    id = newUuid();
    await store.write(_deviceIdKey, id);
  }
  return DeviceDescriptor(
    id: id,
    name: await ref.read(deviceNameProvider.future),
    platform: Platform.isIOS ? 'ios' : 'android',
  );
});

const _deviceIdKey = 'device.id';
const _pcKey = 'pc.current';

/// PC associé (un seul pour le MVP ; multi-PC : #15).
final pairedPcProvider = AsyncNotifierProvider<PairedPcNotifier, PairedAgent?>(PairedPcNotifier.new);

class PairedPcNotifier extends AsyncNotifier<PairedAgent?> {
  @override
  Future<PairedAgent?> build() async {
    final raw = await ref.read(secureStoreProvider).read(_pcKey);
    if (raw == null) return null;
    try {
      return PairedAgent.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PairedAgent pc) async {
    await ref.read(secureStoreProvider).write(_pcKey, jsonEncode(pc.toJson()));
    state = AsyncData(pc);
  }

  /// Oublie le PC : le secret est supprimé du téléphone.
  Future<void> forget() async {
    await ref.read(secureStoreProvider).delete(_pcKey);
    state = const AsyncData(null);
  }
}

/// Message affiché sur l'écran d'association (ex. accès révoqué par le PC).
final pairingNoticeProvider = NotifierProvider<PairingNoticeNotifier, String?>(PairingNoticeNotifier.new);

class PairingNoticeNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void show(String? message) => state = message;
}

/// Connexion maintenue vers le PC associé.
final linkProvider = Provider<PegasusLink>((ref) {
  final link = PegasusLink(appVersion: appVersion);
  ref.onDispose(link.dispose);
  return link;
});

/// État de la connexion ; démarre / arrête le lien selon le PC associé.
final linkStateProvider = NotifierProvider<LinkStateNotifier, LinkState>(LinkStateNotifier.new);

class LinkStateNotifier extends Notifier<LinkState> {
  @override
  LinkState build() {
    final link = ref.watch(linkProvider);
    final sub = link.states.listen((s) {
      state = s;
      // Appareil révoqué (4403) : on supprime le secret et on propose de réassocier.
      if (s.status == LinkStatus.revoked) {
        final name = ref.read(pairedPcProvider).value?.agentName ?? 'Le PC';
        ref.read(pairingNoticeProvider.notifier).show('« $name » a révoqué l’accès de ce téléphone.');
        ref.read(pairedPcProvider.notifier).forget();
      }
    });
    ref.onDispose(sub.cancel);
    ref.listen<AsyncValue<PairedAgent?>>(pairedPcProvider, (prev, next) {
      final pc = next.value;
      final before = prev?.value;
      if (pc == null) {
        if (before != null) link.stop();
      } else if (before == null ||
          before.agentId != pc.agentId ||
          before.deviceSecret != pc.deviceSecret ||
          before.host != pc.host ||
          before.port != pc.port) {
        link.start(pc);
      }
    }, fireImmediately: true);
    return link.state;
  }

  /// Retente tout de suite (retour au premier plan, bouton « Reconnecter »).
  void reconnect() {
    final link = ref.read(linkProvider);
    final pc = ref.read(pairedPcProvider).value;
    if (pc == null) return;
    if (link.state.status == LinkStatus.waiting) {
      link.reconnectNow();
    } else if (!link.state.isConnected && link.state.status != LinkStatus.connecting) {
      link.start(pc);
    }
  }
}
