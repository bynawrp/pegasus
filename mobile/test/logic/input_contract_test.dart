// Contrat app ↔ agent : tout ce que l'app envoie pour le module input doit
// passer la validation de l'agent (mêmes fonctions parse* du protocole).
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/modules/input/input_service.dart';
import 'package:pegasus/src/modules/keyboard/keyboard_module.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

class _Validating implements RemoteSender {
  final ops = <String>[];

  void _check(String op, Map<String, Object?> data) {
    ops.add(op);
    switch (op) {
      case 'input.move':
        parseDelta(data);
      case 'input.scroll':
        parseDelta(data, scroll: true);
      case 'input.button':
        parseButton(data);
      case 'input.click':
        parseClick(data);
      case 'input.text':
        parseText(data);
      case 'input.key':
        parseKey(data);
      default:
        fail('Opération inattendue : $op');
    }
    expect(moduleForOp(op), 'input');
  }

  @override
  void command(String op, Map<String, Object?> data) => _check(op, data);

  @override
  Future<void> request(String op, Map<String, Object?> data) async => _check(op, data);
}

void main() {
  test('chaque message produit par l’app est valide pour l’agent', () async {
    final sender = _Validating();
    final s = InputService(sender);
    s.move(3.3333, -2);
    s.scroll(0, 1.5);
    s.flush();
    for (final b in MouseButton.values) {
      s.button(b, down: true);
      s.button(b, down: false);
      await s.click(b);
    }
    await s.text('Unicode : é 👋 ✓');
    await s.text('x' * 2500);
    await s.key('backspace', repeat: 250);
    for (final k in [...specialKeys, ...shortcutKeys]) {
      await s.key(k.key, modifiers: k.modifiers);
    }
    for (final k in InputKeys.all) {
      await s.key(k, modifiers: KeyModifier.values);
    }
    expect(sender.ops.toSet(), {'input.move', 'input.scroll', 'input.button', 'input.click', 'input.text', 'input.key'});
  });

  test('touches de l’écran clavier : toutes connues du protocole', () {
    for (final k in [...specialKeys, ...shortcutKeys]) {
      expect(InputKeys.isValid(k.key), isTrue, reason: k.label);
    }
  });
}
