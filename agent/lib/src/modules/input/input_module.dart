import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import '../../platform/input_controller.dart';

/// Branche les opérations `input.*` (spec §8) sur le serveur.
///
/// Les données sont validées ici ; une donnée invalide répond `bad_request`
/// (requêtes) ou est ignorée (commandes haute fréquence).
void registerInputModule(AgentServer server, InputController input) {
  T validate<T>(T Function() parse) {
    try {
      return parse();
    } on InputValidationError catch (e) {
      throw OpException(ErrorCode.badRequest, e.message);
    }
  }

  // Commandes (sans réponse).
  server.onCommand('input.move', (_, data) {
    final d = parseDelta(data);
    input.move(d.dx, d.dy);
  });
  server.onCommand('input.scroll', (_, data) {
    final d = parseDelta(data, scroll: true);
    input.scroll(d.dx, d.dy);
  });
  server.onCommand('input.button', (_, data) {
    final b = parseButton(data);
    input.button(b.button, down: b.down);
  });

  // Requêtes.
  server.onRequest('input.click', (_, data) {
    final c = validate(() => parseClick(data));
    input.click(c.button, count: c.count);
    return null;
  });
  server.onRequest('input.text', (_, data) {
    input.text(validate(() => parseText(data)));
    return null;
  });
  server.onRequest('input.key', (_, data) {
    final k = validate(() => parseKey(data));
    input.key(k.key, k.modifiers, repeat: k.repeat);
    return null;
  });
}
