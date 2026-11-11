import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Envelope', () {
    test('requête : aller-retour JSON', () {
      final e = Envelope.decode(Envelope.request('42', 'power.lock').encode());
      expect(e.type, MessageType.request);
      expect(e.id, '42');
      expect(e.op, 'power.lock');
      expect(e.data, isEmpty);
    });

    test('commande : pas d\'id', () {
      final json = Envelope.command('input.move', {'dx': 3.5, 'dy': -1}).toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['data'], {'dx': 3.5, 'dy': -1});
    });

    test('réponse en échec : code d\'erreur conservé', () {
      final e = Envelope.decode(Envelope.fail('7', ErrorCode.forbidden, 'Module désactivé').encode());
      expect(e.ok, isFalse);
      expect(e.error!.code, ErrorCode.forbidden);
      expect(e.error!.message, 'Module désactivé');
    });

    test('champs inconnus ignorés', () {
      final e = Envelope.decode('{"v":1,"type":"evt","op":"audio.changed","data":{"volume":60},"futur":true}');
      expect(e.op, 'audio.changed');
      expect(e.data['volume'], 60);
    });

    test('messages invalides refusés', () {
      expect(() => Envelope.decode('pas du json'), throwsFormatException);
      expect(() => Envelope.decode('[1,2]'), throwsFormatException);
      expect(() => Envelope.decode('{"type":"req","id":"1","op":"x"}'), throwsFormatException);
      expect(() => Envelope.decode('{"v":1,"type":"req","op":"x"}'), throwsFormatException);
      expect(() => Envelope.decode('{"v":1,"type":"res","id":"1"}'), throwsFormatException);
      expect(() => Envelope.decode('{"v":1,"type":"bidon","op":"x"}'), throwsFormatException);
    });

    test('code d\'erreur inconnu → internal', () {
      expect(ErrorCode.fromWire('nouveau_code'), ErrorCode.internal);
    });
  });

  group('moduleForOp', () {
    test('correspondance des préfixes (spec §7)', () {
      expect(moduleForOp('input.move'), 'input');
      expect(moduleForOp('audio.set'), 'media');
      expect(moduleForOp('media.next'), 'media');
      expect(moduleForOp('power.shutdown'), 'power');
      expect(moduleForOp('url.open'), 'apps');
      expect(moduleForOp('session.auth'), isNull);
      expect(moduleForOp('agent.info'), isNull);
    });
  });
}
