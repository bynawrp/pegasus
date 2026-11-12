import 'dart:async';

import 'package:pegasus_protocol/pegasus_protocol.dart';

/// Jeton (QR) et code manuel d'appairage en cours.
class PairingSecret {
  const PairingSecret({required this.token, required this.code, required this.expiresAt});

  final String token;
  final String code;
  final DateTime expiresAt;
}

enum PairingCheck { ok, invalid, expired, locked }

/// Gère le jeton et le code d'appairage (spec §3, §9) : usage unique,
/// 5 minutes, invalidés après 5 échecs jusqu'à régénération.
class PairingManager {
  PairingManager({
    this.ttl = PairingInvite.ttl,
    this.maxFailures = PairingInvite.maxFailures,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int maxFailures;
  final DateTime Function() _clock;
  final _changes = StreamController<PairingSecret?>.broadcast();

  PairingSecret? _current;
  int _failures = 0;
  bool _locked = false;

  /// Secret courant, `null` s'il a été utilisé, invalidé ou n'existe pas encore.
  PairingSecret? get current {
    final c = _current;
    if (c != null && !_clock().isBefore(c.expiresAt)) return null;
    return c;
  }

  /// Vrai après [maxFailures] échecs : il faut appeler [renew].
  bool get locked => _locked;

  Stream<PairingSecret?> get changes => _changes.stream;

  /// Nouveau jeton + code, réinitialise le compteur d'échecs.
  PairingSecret renew() {
    _failures = 0;
    _locked = false;
    _current = PairingSecret(
      token: PegasusCrypto.randomToken(16),
      code: PegasusCrypto.randomCode(),
      expiresAt: _clock().add(ttl),
    );
    _changes.add(_current);
    return _current!;
  }

  /// Vérifie un jeton ou un code ; en cas de succès le secret est consommé.
  PairingCheck consume({String? token, String? code}) {
    if (_locked) return PairingCheck.locked;
    final c = _current;
    if (c == null) return PairingCheck.invalid;
    if (!_clock().isBefore(c.expiresAt)) return PairingCheck.expired;

    final valid = (token != null && PegasusCrypto.constantTimeEquals(token, c.token)) ||
        (code != null && PegasusCrypto.constantTimeEquals(code, c.code));
    if (valid) {
      _current = null;
      _changes.add(null);
      return PairingCheck.ok;
    }
    _failures++;
    if (_failures >= maxFailures) {
      _locked = true;
      _current = null;
      _changes.add(null);
      return PairingCheck.locked;
    }
    return PairingCheck.invalid;
  }

  Future<void> dispose() => _changes.close();
}
