/// Opérations des modules `media`, `power` et `apps` (spec §8) : validation
/// partagée par l'app et l'agent.
library;

import 'input.dart' show InputValidationError;

/// État du son du PC.
class AudioState {
  const AudioState({required this.volume, required this.muted});

  /// 0 à 100.
  final int volume;
  final bool muted;

  Map<String, Object?> toJson() => {'volume': volume, 'muted': muted};

  static AudioState fromJson(Map<String, Object?> json) => AudioState(
        volume: (json['volume'] as num? ?? 0).round().clamp(0, 100),
        muted: json['muted'] == true,
      );

  @override
  bool operator ==(Object other) => other is AudioState && other.volume == volume && other.muted == muted;
  @override
  int get hashCode => Object.hash(volume, muted);
  @override
  String toString() => 'AudioState($volume${muted ? ', muet' : ''})';
}

/// `audio.set` : `{ volume?: 0-100, muted?: bool }`, au moins un des deux.
({int? volume, bool? muted}) parseAudioSet(Map<String, Object?> data) {
  final v = data['volume'];
  final m = data['muted'];
  if (v == null && m == null) throw const InputValidationError('« volume » ou « muted » requis');
  if (v != null && (v is! num || v.isNaN || v < 0 || v > 100)) {
    throw const InputValidationError('« volume » doit être entre 0 et 100');
  }
  if (m != null && m is! bool) throw const InputValidationError('« muted » doit être un booléen');
  return (volume: (v as num?)?.round(), muted: m as bool?);
}

/// Actions d'alimentation.
enum PowerAction {
  lock(destructive: false),
  sleep(destructive: false),
  logoff(destructive: true),
  restart(destructive: true),
  shutdown(destructive: true);

  const PowerAction({required this.destructive});

  /// Exige `confirmed: true` (confirmation affichée par l'app).
  final bool destructive;

  String get op => 'power.$name';

  static PowerAction? fromOp(String op) => values.where((a) => a.op == op).firstOrNull;
}

/// Vérifie la confirmation d'une action d'alimentation destructrice.
void checkPowerConfirmation(PowerAction action, Map<String, Object?> data) {
  if (action.destructive && data['confirmed'] != true) {
    throw const InputValidationError('Confirmation requise (« confirmed: true »)');
  }
}

/// Touches multimédia.
enum MediaCommand {
  playPause('media.play_pause'),
  next('media.next'),
  previous('media.previous');

  const MediaCommand(this.op);
  final String op;
}

/// URL limitée (spec §8).
abstract final class UrlLimits {
  static const maxLength = 2048;
}

/// `url.open` : `{ url }` en http(s), 2048 caractères max.
Uri parseUrl(Map<String, Object?> data) {
  final raw = data['url'];
  if (raw is! String || raw.trim().isEmpty) throw const InputValidationError('« url » manquante');
  final url = raw.trim();
  if (url.length > UrlLimits.maxLength) throw const InputValidationError('Lien trop long (2048 caractères max)');
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    throw const InputValidationError('Seuls les liens http:// et https:// sont acceptés');
  }
  return uri;
}

/// Premier lien http(s) trouvé dans un texte partagé (ex. « Regarde ça https://… »).
String? extractUrl(String text) {
  final m = RegExp(r'https?://[^\s<>"]+', caseSensitive: false).firstMatch(text);
  if (m == null) return null;
  // Ponctuation de fin de phrase exclue.
  return m.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
}

/// `apps.launch` : `{ id }`.
String parseAppId(Map<String, Object?> data) {
  final id = data['id'];
  if (id is! String || id.isEmpty || id.length > 128) throw const InputValidationError('« id » invalide');
  return id;
}

/// Application favorite telle que vue par l'app.
class FavoriteApp {
  const FavoriteApp({required this.id, required this.name, this.icon});

  final String id;
  final String name;

  /// PNG en base64 (peut être absent).
  final String? icon;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'icon': ?icon};

  static FavoriteApp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], icon = raw['icon'];
    if (id is! String || name is! String) return null;
    return FavoriteApp(id: id, name: name, icon: icon is String && icon.isNotEmpty ? icon : null);
  }
}
