import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

/// Identité TLS et stable de l'agent (spec §1) : certificat ECDSA P-256
/// auto-signé valable 10 ans, identifiant UUID, nom affiché.
class AgentIdentity {
  AgentIdentity({
    required this.agentId,
    required this.name,
    required this.certificatePem,
    required this.privateKeyPem,
  }) : fingerprint = PegasusCrypto.fingerprint(_derFromPem(certificatePem));

  final String agentId;
  final String name;
  final String certificatePem;
  final String privateKeyPem;

  /// SHA-256 du certificat DER, base64url sans padding.
  final String fingerprint;

  static const validityDays = 3650;

  /// Génère une nouvelle identité (nouvel identifiant si [agentId] est nul).
  static AgentIdentity generate({required String name, String? agentId}) {
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem({'CN': 'Pegasus Agent'}, privateKey, publicKey);
    final serial = PegasusCrypto.fromB64url(PegasusCrypto.randomToken(8))
        .fold<BigInt>(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));
    final cert = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      validityDays,
      serialNumber: (serial + BigInt.one).toString(),
      notBefore: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    );
    return AgentIdentity(
      agentId: agentId ?? newUuid(),
      name: name,
      certificatePem: cert,
      privateKeyPem: CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
    );
  }

  AgentIdentity rename(String newName) => AgentIdentity(
        agentId: agentId,
        name: newName,
        certificatePem: certificatePem,
        privateKeyPem: privateKeyPem,
      );

  /// Contexte TLS du serveur.
  SecurityContext securityContext() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  Map<String, Object?> toJson() => {
        'agentId': agentId,
        'name': name,
        'certificate': certificatePem,
        'privateKey': privateKeyPem,
      };

  factory AgentIdentity.fromJson(Map<String, Object?> json) => AgentIdentity(
        agentId: json['agentId'] as String,
        name: json['name'] as String,
        certificatePem: json['certificate'] as String,
        privateKeyPem: json['privateKey'] as String,
      );

  static List<int> _derFromPem(String pem) {
    final body = pem
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return base64.decode(body);
  }
}

/// UUID v4 aléatoire.
String newUuid() {
  final b = PegasusCrypto.fromB64url(PegasusCrypto.randomToken(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
