import 'dart:io';

import 'package:pegasus_protocol/pegasus_protocol.dart';

import 'windows/windows_system.dart';

/// Son, touches multimédia, alimentation, lancement d'applications et de liens.
/// Une implémentation par OS (Windows aujourd'hui, #1 pour macOS / Linux).
abstract class SystemController {
  AudioState audio();
  AudioState setAudio({int? volume, bool? muted});
  void media(MediaCommand command);

  /// Exécute l'action d'alimentation (l'agent a déjà répondu au téléphone).
  void power(PowerAction action);

  /// Ouvre un raccourci / une application ; `false` si Windows refuse.
  bool launch(String path);

  /// Ouvre un lien http(s) dans le navigateur par défaut.
  bool openUrl(Uri url);

  static SystemController? platform() => Platform.isWindows ? WindowsSystem() : null;
}

/// Enregistre les appels, sans rien exécuter (tests).
class RecordingSystemController implements SystemController {
  final calls = <String>[];
  AudioState state = const AudioState(volume: 50, muted: false);
  bool launchResult = true;

  @override
  AudioState audio() => state;

  @override
  AudioState setAudio({int? volume, bool? muted}) {
    calls.add('audio ${volume ?? '-'} ${muted ?? '-'}');
    return state = AudioState(volume: volume ?? state.volume, muted: muted ?? state.muted);
  }

  @override
  void media(MediaCommand command) => calls.add('media ${command.name}');

  @override
  void power(PowerAction action) => calls.add('power ${action.name}');

  @override
  bool launch(String path) {
    calls.add('launch $path');
    return launchResult;
  }

  @override
  bool openUrl(Uri url) {
    calls.add('url $url');
    return true;
  }
}
