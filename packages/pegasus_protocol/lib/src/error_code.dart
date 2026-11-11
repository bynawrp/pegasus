/// Codes d'erreur renvoyés dans une réponse `res` en échec (spec §6).
enum ErrorCode {
  badRequest('bad_request'),
  unauthorized('unauthorized'),
  forbidden('forbidden'),
  paused('paused'),
  rejected('rejected'),
  notSupported('not_supported'),
  rateLimited('rate_limited'),
  internal('internal');

  const ErrorCode(this.wire);

  /// Valeur transmise sur le réseau.
  final String wire;

  /// Retrouve un code depuis sa valeur réseau ; inconnu → [internal].
  static ErrorCode fromWire(String value) =>
      values.firstWhere((c) => c.wire == value, orElse: () => internal);
}
