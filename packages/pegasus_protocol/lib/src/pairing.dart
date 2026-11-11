/// Invitation d'appairage portée par le QR code (spec §3).
///
/// `pegasus://pair?v=1&h=<hôte>&p=<port>&id=<agentId>&n=<nom>&fp=<empreinte>&t=<jeton>`
class PairingInvite {
  const PairingInvite({
    required this.host,
    required this.port,
    required this.agentId,
    required this.agentName,
    required this.fingerprint,
    required this.token,
    this.version = 1,
  });

  static const scheme = 'pegasus';

  /// Durée de validité d'un jeton ou d'un code d'appairage.
  static const ttl = Duration(minutes: 5);

  /// Nombre d'échecs avant invalidation du jeton / code.
  static const maxFailures = 5;

  final int version;
  final String host;
  final int port;
  final String agentId;
  final String agentName;
  final String fingerprint;
  final String token;

  Uri toUri() => Uri(
        scheme: scheme,
        host: 'pair',
        queryParameters: {
          'v': '$version',
          'h': host,
          'p': '$port',
          'id': agentId,
          'n': agentName,
          'fp': fingerprint,
          't': token,
        },
      );

  @override
  String toString() => toUri().toString();

  /// Lit le contenu d'un QR code. Lève une [FormatException] si ce n'est pas
  /// une invitation Pegasus valide.
  factory PairingInvite.parse(String raw) {
    final Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } on FormatException {
      throw const FormatException('QR code illisible');
    }
    if (uri.scheme != scheme || uri.host != 'pair') {
      throw const FormatException("Ce QR code n'est pas un code Pegasus");
    }
    final q = uri.queryParameters;
    String req(String key) {
      final value = q[key];
      if (value == null || value.isEmpty) {
        throw FormatException('Paramètre « $key » manquant');
      }
      return value;
    }

    final version = int.tryParse(req('v'));
    final port = int.tryParse(req('p'));
    if (version == null) throw const FormatException('Version invalide');
    if (port == null || port < 1 || port > 65535) throw const FormatException('Port invalide');
    return PairingInvite(
      version: version,
      host: req('h'),
      port: port,
      agentId: req('id'),
      agentName: req('n'),
      fingerprint: req('fp'),
      token: req('t'),
    );
  }
}
