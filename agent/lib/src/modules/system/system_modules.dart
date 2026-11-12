import 'dart:async';

import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import '../../platform/system_controller.dart';
import '../apps/app_catalog.dart';

T _validate<T>(T Function() parse) {
  try {
    return parse();
  } on InputValidationError catch (e) {
    throw OpException(ErrorCode.badRequest, e.message);
  }
}

/// Module `media` : touches multimédia et volume général (spec §8).
void registerMediaModule(AgentServer server, SystemController system) {
  for (final command in MediaCommand.values) {
    server.onRequest(command.op, (_, _) {
      system.media(command);
      return null;
    });
  }
  server.onRequest('audio.get', (_, _) => _audio(() => system.audio()).toJson());
  server.onRequest('audio.set', (_, data) {
    final req = _validate(() => parseAudioSet(data));
    final state = _audio(() => system.setAudio(volume: req.volume, muted: req.muted));
    server.broadcast(Envelope.event('audio.changed', state.toJson()));
    return state.toJson();
  });
}

AudioState _audio(AudioState Function() read) {
  try {
    return read();
  } catch (_) {
    throw const OpException(ErrorCode.notSupported, 'Aucune sortie audio disponible');
  }
}

/// Module `power` : l'agent répond **avant** d'exécuter (spec §8), après
/// [delay] pour laisser partir la réponse.
void registerPowerModule(AgentServer server, SystemController system,
    {Duration delay = const Duration(milliseconds: 600)}) {
  for (final action in PowerAction.values) {
    server.onRequest(action.op, (_, data) {
      _validate(() => checkPowerConfirmation(action, data));
      Timer(delay, () => system.power(action));
      return null;
    });
  }
}

/// Module `apps` : favoris configurés sur l'agent et ouverture de liens.
void registerAppsModule(AgentServer server, SystemController system, List<Favorite> Function() favorites) {
  server.onRequest('apps.list', (_, _) => {
        'apps': [for (final f in favorites()) f.toWire().toJson()],
      });
  server.onRequest('apps.launch', (_, data) {
    final id = _validate(() => parseAppId(data));
    // Jamais de chemin arbitraire : uniquement un favori connu (spec §8).
    final fav = favorites().where((f) => f.id == id).firstOrNull;
    if (fav == null) throw const OpException(ErrorCode.badRequest, 'Application inconnue');
    if (!system.launch(fav.path)) throw OpException(ErrorCode.rejected, 'Impossible de lancer ${fav.name}');
    return null;
  });
  server.onRequest('url.open', (_, data) {
    final url = _validate(() => parseUrl(data));
    if (!system.openUrl(url)) throw const OpException(ErrorCode.rejected, 'Impossible d’ouvrir le lien');
    return null;
  });
}

/// Surveille le volume du PC et prévient les téléphones quand il change
/// (molette, clavier, autre application).
class AudioWatcher {
  AudioWatcher(this.server, this.system, {this.interval = const Duration(milliseconds: 700)});

  final AgentServer server;
  final SystemController system;
  final Duration interval;
  Timer? _timer;
  AudioState? _last;

  void start() => _timer ??= Timer.periodic(interval, (_) => poll());

  void poll() {
    if (server.sessions.isEmpty) {
      _last = null;
      return;
    }
    final AudioState now;
    try {
      now = system.audio();
    } catch (_) {
      return;
    }
    if (_last != null && now != _last) {
      server.broadcast(Envelope.event('audio.changed', now.toJson()));
    }
    _last = now;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
