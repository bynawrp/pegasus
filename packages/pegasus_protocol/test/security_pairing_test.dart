import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PegasusCrypto', () {
    test('b64url sans padding, aller-retour', () {
      final bytes = List<int>.generate(31, (i) => i * 7 % 256);
      final s = PegasusCrypto.b64url(bytes);
      expect(s.contains('='), isFalse);
      expect(PegasusCrypto.fromB64url(s), bytes);
    });

    test('randomToken : longueur et unicité', () {
      final a = PegasusCrypto.randomToken(16);
      expect(PegasusCrypto.fromB64url(a).length, 16);
      expect(a, isNot(PegasusCrypto.randomToken(16)));
    });

    test('randomCode : 6 chiffres', () {
      for (var i = 0; i < 50; i++) {
        expect(PegasusCrypto.randomCode(), matches(RegExp(r'^\d{6}$')));
      }
    });

    test('authMac : déterministe et sensible à chaque entrée', () {
      final secret = PegasusCrypto.b64url(List.filled(32, 1));
      final nonce = PegasusCrypto.b64url(List.filled(32, 2));
      String mac({String a = 'a', String d = 'd', String? n}) => PegasusCrypto.authMac(
          deviceSecret: secret, nonce: n ?? nonce, agentId: a, deviceId: d);
      expect(mac(), mac());
      expect(mac(), isNot(mac(a: 'b')));
      expect(mac(), isNot(mac(d: 'e')));
      expect(mac(), isNot(mac(n: PegasusCrypto.b64url(List.filled(32, 3)))));
      expect(PegasusCrypto.fromB64url(mac()).length, 32);
    });

    test('constantTimeEquals', () {
      expect(PegasusCrypto.constantTimeEquals('abc', 'abc'), isTrue);
      expect(PegasusCrypto.constantTimeEquals('abc', 'abd'), isFalse);
      expect(PegasusCrypto.constantTimeEquals('abc', 'ab'), isFalse);
    });

    test('shortFingerprint : 8 caractères', () {
      expect(PegasusCrypto.shortFingerprint('ABCDEFGHIJK'), 'ABCDEFGH');
    });
  });

  group('PairingInvite', () {
    const invite = PairingInvite(
      host: '192.168.1.20',
      port: 47800,
      agentId: '0b1c-uuid',
      agentName: 'PC Bureau & Jeux',
      fingerprint: 'abc_DEF-123',
      token: 'tok_en-xyz',
    );

    test('aller-retour URI (nom avec espaces et symboles)', () {
      final parsed = PairingInvite.parse(invite.toString());
      expect(parsed.host, invite.host);
      expect(parsed.port, invite.port);
      expect(parsed.agentId, invite.agentId);
      expect(parsed.agentName, invite.agentName);
      expect(parsed.fingerprint, invite.fingerprint);
      expect(parsed.token, invite.token);
      expect(invite.toString(), startsWith('pegasus://pair?v=1&h=192.168.1.20&p=47800'));
    });

    test('rejette un QR étranger ou incomplet', () {
      expect(() => PairingInvite.parse('https://example.com'), throwsFormatException);
      expect(() => PairingInvite.parse('pegasus://pair?v=1&h=x&p=1'), throwsFormatException);
      expect(
        () => PairingInvite.parse(invite.toString().replaceFirst('p=47800', 'p=99999')),
        throwsFormatException,
      );
    });
  });
}
