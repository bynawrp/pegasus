/// Protocole Pegasus v1, partagé entre l'app mobile et l'agent PC.
///
/// Spécification : `docs/protocol.md`.
library;

export 'src/close_codes.dart';
export 'src/envelope.dart';
export 'src/error_code.dart';
export 'src/input.dart';
export 'src/modules.dart';
export 'src/pairing.dart';
export 'src/security.dart';

/// Version majeure du protocole implémentée par ce package.
const int protocolVersion = 1;

/// Port réseau par défaut de l'agent.
const int defaultPort = 47800;

/// Taille maximale d'un message (spec §1).
const int maxMessageBytes = 64 * 1024;
