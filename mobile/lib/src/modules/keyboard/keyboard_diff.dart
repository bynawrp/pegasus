import 'package:characters/characters.dart';

/// Action clavier à rejouer sur le PC.
sealed class KeyAction {
  const KeyAction();
}

class TypeText extends KeyAction {
  const TypeText(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is TypeText && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'text("$text")';
}

class PressKey extends KeyAction {
  const PressKey(this.key, [this.repeat = 1]);
  final String key;
  final int repeat;

  @override
  bool operator ==(Object other) => other is PressKey && other.key == key && other.repeat == repeat;
  @override
  int get hashCode => Object.hash(key, repeat);
  @override
  String toString() => repeat == 1 ? key : '$key×$repeat';
}

/// Actions qui transforment [before] en [after] sur le PC, en supposant le
/// curseur du PC en fin de texte (frappe en direct, corrections auto,
/// modification au milieu du mot).
///
/// Travaille en caractères visibles (graphèmes) : un emoji = un retour arrière.
List<KeyAction> diffText(String before, String after) {
  if (before == after) return const [];
  final a = before.characters.toList();
  final b = after.characters.toList();

  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }
  final deleted = a.length - prefix - suffix;
  final inserted = b.sublist(prefix, b.length - suffix).join();

  return [
    if (suffix > 0) PressKey('left', suffix),
    if (deleted > 0) PressKey('backspace', deleted),
    if (inserted.isNotEmpty) TypeText(inserted),
    if (suffix > 0) PressKey('right', suffix),
  ];
}
