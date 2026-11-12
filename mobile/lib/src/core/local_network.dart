import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Accès au réseau local (autorisation iOS 14+ ; toujours accordé sur Android).
enum LocalNetworkAccess {
  /// Demande affichée, en attente de la réponse de l'utilisateur.
  checking,
  granted,
  denied,
}

/// Accès natif à l'autorisation (remplacé par un faux dans les tests).
abstract class LocalNetworkPermission {
  /// Déclenche la demande si besoin et renvoie la réponse.
  Future<bool> request();

  /// Ouvre les réglages de l'app.
  Future<void> openSettings();
}

class PlatformLocalNetworkPermission implements LocalNetworkPermission {
  const PlatformLocalNetworkPermission();

  static const _channel = MethodChannel('pegasus/local_network');

  @override
  Future<bool> request() async {
    if (!Platform.isIOS) return true;
    try {
      return await _channel.invokeMethod<bool>('request') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> openSettings() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }
}

final localNetworkPermissionProvider =
    Provider<LocalNetworkPermission>((ref) => const PlatformLocalNetworkPermission());

/// État de l'autorisation, demandée dès l'ouverture de l'app.
final localNetworkProvider =
    NotifierProvider<LocalNetworkNotifier, LocalNetworkAccess>(LocalNetworkNotifier.new);

class LocalNetworkNotifier extends Notifier<LocalNetworkAccess> {
  bool _running = false;

  @override
  LocalNetworkAccess build() {
    Future.microtask(check);
    return LocalNetworkAccess.checking;
  }

  /// (Re)vérifie l'autorisation : au lancement et au retour des réglages.
  Future<void> check() async {
    if (_running) return;
    _running = true;
    try {
      final granted = await ref.read(localNetworkPermissionProvider).request();
      if (ref.mounted) state = granted ? LocalNetworkAccess.granted : LocalNetworkAccess.denied;
    } finally {
      _running = false;
    }
  }

  Future<void> openSettings() => ref.read(localNetworkPermissionProvider).openSettings();
}
