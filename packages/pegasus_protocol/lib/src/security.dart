import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Primitives de sécurité du protocole (spec §1, §3, §4).
abstract final class PegasusCrypto {
  static final Random _random = Random.secure();

  /// Encodage base64url sans padding.
  static String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// Décode du base64url avec ou sans padding.
  static Uint8List fromB64url(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(padded);
  }

  /// [length] octets aléatoires (CSPRNG), encodés en base64url.
  static String randomToken([int length = 32]) =>
      b64url(List<int>.generate(length, (_) => _random.nextInt(256)));

  /// Code manuel d'appairage : 6 chiffres.
  static String randomCode() => _random.nextInt(1000000).toString().padLeft(6, '0');

  /// Empreinte d'un certificat : SHA-256 du DER, base64url sans padding.
  static String fingerprint(List<int> der) => b64url(sha256.convert(der).bytes);

  /// Les 8 premiers caractères de l'empreinte, comparés à l'œil (code manuel).
  static String shortFingerprint(String fingerprint) =>
      fingerprint.length <= 8 ? fingerprint : fingerprint.substring(0, 8);

  /// `base64url(HMAC-SHA256(deviceSecret, nonce ‖ agentId ‖ deviceId))`.
  ///
  /// [deviceSecret] et [nonce] sont en base64url ; le message est formé des
  /// octets du nonce suivis des identifiants en UTF-8.
  static String authMac({
    required String deviceSecret,
    required String nonce,
    required String agentId,
    required String deviceId,
  }) {
    final hmac = Hmac(sha256, fromB64url(deviceSecret));
    final message = <int>[
      ...fromB64url(nonce),
      ...utf8.encode(agentId),
      ...utf8.encode(deviceId),
    ];
    return b64url(hmac.convert(message).bytes);
  }

  /// Comparaison en temps constant.
  static bool constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    if (x.length != y.length) return false;
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}
