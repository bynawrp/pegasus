/// Opérations du module `input` (spec §8) : modèles et validation partagés
/// par l'app (construction) et l'agent (validation des données reçues).
library;

enum MouseButton {
  left,
  right,
  middle;

  static MouseButton? parse(Object? v) => values.where((b) => b.name == v).firstOrNull;
}

enum KeyModifier {
  ctrl,
  alt,
  shift,
  win;

  static KeyModifier? parse(Object? v) => values.where((m) => m.name == v).firstOrNull;
}

/// Noms de touches acceptés par `input.key`.
abstract final class InputKeys {
  static const special = [
    'escape', 'tab', 'enter', 'backspace', 'delete', 'space', //
    'up', 'down', 'left', 'right', 'home', 'end', 'pageup', 'pagedown',
    'printscreen', 'win',
  ];
  static final function = [for (var i = 1; i <= 12; i++) 'f$i'];
  static final letters = [for (var c = 0x61; c <= 0x7a; c++) String.fromCharCode(c)];
  static final digits = [for (var c = 0; c <= 9; c++) '$c'];

  static final Set<String> all = {...special, ...function, ...letters, ...digits};

  static bool isValid(Object? key) => key is String && all.contains(key);
}

/// Limites (spec §8).
abstract final class InputLimits {
  static const maxTextLength = 1000;

  /// Répétitions d'une touche dans un seul `input.key` (ex. 8 × Retour arrière).
  static const maxRepeat = 100;

  /// Bornes de sécurité d'un déplacement / défilement par message.
  static const maxMove = 2000.0;
  static const maxScroll = 50.0;
}

/// Erreur de validation : renvoyée en `bad_request`.
class InputValidationError implements Exception {
  const InputValidationError(this.message);
  final String message;

  @override
  String toString() => message;
}

double _number(Map<String, Object?> data, String key, double max) {
  final v = data[key] ?? 0;
  if (v is! num || v.isNaN || v.isInfinite) throw InputValidationError('« $key » doit être un nombre');
  return v.toDouble().clamp(-max, max);
}

/// `input.move` / `input.scroll` : `{ dx, dy }`.
({double dx, double dy}) parseDelta(Map<String, Object?> data, {bool scroll = false}) {
  final max = scroll ? InputLimits.maxScroll : InputLimits.maxMove;
  return (dx: _number(data, 'dx', max), dy: _number(data, 'dy', max));
}

/// `input.button` : `{ button, state: "down"|"up" }`.
({MouseButton button, bool down}) parseButton(Map<String, Object?> data) {
  final button = MouseButton.parse(data['button']);
  if (button == null) throw const InputValidationError('« button » invalide');
  final state = data['state'];
  if (state != 'down' && state != 'up') throw const InputValidationError('« state » doit valoir down ou up');
  return (button: button, down: state == 'down');
}

/// `input.click` : `{ button, count: 1|2 }`.
({MouseButton button, int count}) parseClick(Map<String, Object?> data) {
  final button = MouseButton.parse(data['button'] ?? 'left');
  if (button == null) throw const InputValidationError('« button » invalide');
  final count = data['count'] ?? 1;
  if (count != 1 && count != 2) throw const InputValidationError('« count » doit valoir 1 ou 2');
  return (button: button, count: count as int);
}

/// `input.text` : `{ text }`, 1000 caractères max.
String parseText(Map<String, Object?> data) {
  final text = data['text'];
  if (text is! String || text.isEmpty) throw const InputValidationError('« text » manquant');
  if (text.runes.length > InputLimits.maxTextLength) {
    throw const InputValidationError('Texte trop long (1000 caractères max)');
  }
  return text;
}

/// `input.key` : `{ key, modifiers: [...], repeat?: 1..100 }`.
({String key, List<KeyModifier> modifiers, int repeat}) parseKey(Map<String, Object?> data) {
  final key = data['key'];
  if (!InputKeys.isValid(key)) throw InputValidationError('Touche inconnue : $key');
  final raw = data['modifiers'] ?? const [];
  if (raw is! List) throw const InputValidationError('« modifiers » doit être une liste');
  final modifiers = <KeyModifier>[];
  for (final m in raw) {
    final mod = KeyModifier.parse(m);
    if (mod == null) throw InputValidationError('Modificateur inconnu : $m');
    if (!modifiers.contains(mod)) modifiers.add(mod);
  }
  final repeat = data['repeat'] ?? 1;
  if (repeat is! int || repeat < 1 || repeat > InputLimits.maxRepeat) {
    throw const InputValidationError('« repeat » doit être entre 1 et 100');
  }
  return (key: key as String, modifiers: modifiers, repeat: repeat);
}
