/// Codes de fermeture WebSocket propres à Pegasus (spec §5).
abstract final class CloseCodes {
  static const int badHandshake = 4400;
  static const int unauthorized = 4401;
  static const int revoked = 4403;
  static const int handshakeTimeout = 4408;
  static const int replaced = 4409;
  static const int unsupportedVersion = 4426;
}
