import 'dart:io';

import 'package:pegasus_protocol/pegasus_protocol.dart';

import 'windows/windows_input.dart';

/// Pilotage de la souris et du clavier du PC (module `input`).
///
/// Une implémentation par OS (Windows aujourd'hui, #1 pour macOS / Linux).
abstract class InputController {
  /// Déplacement relatif en pixels (décimaux cumulés).
  void move(double dx, double dy);

  /// Défilement en crans ; `dy > 0` fait défiler vers le bas, `dx > 0` vers la droite.
  void scroll(double dx, double dy);

  void button(MouseButton button, {required bool down});
  void click(MouseButton button, {int count = 1});

  /// Saisit du texte Unicode tel quel (indépendant de la disposition clavier).
  void text(String text);

  /// Appuie [repeat] fois sur une touche avec des modificateurs (ex. Alt+Tab).
  void key(String key, List<KeyModifier> modifiers, {int repeat = 1});

  /// Contrôleur de la plateforme courante, ou `null` si non supportée.
  static InputController? platform() => Platform.isWindows ? WindowsInputController() : null;
}

/// Enregistre les appels (tests).
class RecordingInputController implements InputController {
  final calls = <String>[];

  @override
  void move(double dx, double dy) => calls.add('move $dx $dy');

  @override
  void scroll(double dx, double dy) => calls.add('scroll $dx $dy');

  @override
  void button(MouseButton button, {required bool down}) =>
      calls.add('button ${button.name} ${down ? 'down' : 'up'}');

  @override
  void click(MouseButton button, {int count = 1}) => calls.add('click ${button.name} $count');

  @override
  void text(String text) => calls.add('text $text');

  @override
  void key(String key, List<KeyModifier> modifiers, {int repeat = 1}) =>
      calls.add('key ${[...modifiers.map((m) => m.name), key].join('+')}${repeat > 1 ? ' x$repeat' : ''}');
}
