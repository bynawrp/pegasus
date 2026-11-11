import 'dart:convert';

import 'error_code.dart';

/// Type d'un message (spec §2).
enum MessageType {
  request('req'),
  response('res'),
  command('cmd'),
  event('evt');

  const MessageType(this.wire);
  final String wire;

  static MessageType fromWire(String value) => values.firstWhere(
        (t) => t.wire == value,
        orElse: () => throw FormatException('Type de message inconnu : $value'),
      );
}

/// Erreur portée par une réponse en échec.
class ProtocolError {
  const ProtocolError(this.code, [this.message = '']);

  final ErrorCode code;
  final String message;

  Map<String, Object?> toJson() => {'code': code.wire, 'message': message};

  factory ProtocolError.fromJson(Map<String, Object?> json) => ProtocolError(
        ErrorCode.fromWire(json['code'] as String? ?? ''),
        json['message'] as String? ?? '',
      );
}

/// Enveloppe commune à tous les messages Pegasus.
class Envelope {
  const Envelope._({
    required this.type,
    this.v = 1,
    this.id,
    this.op,
    this.data = const {},
    this.ok,
    this.error,
  });

  /// Requête : attend une réponse portant le même [id].
  factory Envelope.request(String id, String op, [Map<String, Object?> data = const {}]) =>
      Envelope._(type: MessageType.request, id: id, op: op, data: data);

  /// Commande haute fréquence, sans réponse.
  factory Envelope.command(String op, [Map<String, Object?> data = const {}]) =>
      Envelope._(type: MessageType.command, op: op, data: data);

  /// Événement poussé par l'agent.
  factory Envelope.event(String op, [Map<String, Object?> data = const {}]) =>
      Envelope._(type: MessageType.event, op: op, data: data);

  /// Réponse réussie à la requête [id].
  factory Envelope.ok(String id, [Map<String, Object?> data = const {}]) =>
      Envelope._(type: MessageType.response, id: id, ok: true, data: data);

  /// Réponse en échec à la requête [id].
  factory Envelope.fail(String id, ErrorCode code, [String message = '']) =>
      Envelope._(type: MessageType.response, id: id, ok: false, error: ProtocolError(code, message));

  final int v;
  final MessageType type;
  final String? id;
  final String? op;
  final Map<String, Object?> data;
  final bool? ok;
  final ProtocolError? error;

  Map<String, Object?> toJson() => {
        'v': v,
        'type': type.wire,
        if (id != null) 'id': id,
        if (op != null) 'op': op,
        if (ok != null) 'ok': ok,
        if (error != null) 'error': error!.toJson() else 'data': data,
      };

  String encode() => jsonEncode(toJson());

  /// Décode un message reçu. Les champs inconnus sont ignorés (spec §2).
  ///
  /// Lève une [FormatException] si le message est invalide.
  factory Envelope.decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('JSON invalide');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Le message doit être un objet JSON');
    }
    final v = json['v'];
    if (v is! int) throw const FormatException('Champ « v » manquant ou invalide');

    final type = MessageType.fromWire(json['type'] as String? ?? '');
    final id = json['id'] as String?;
    final op = json['op'] as String?;
    final data = (json['data'] as Map<String, Object?>?) ?? const {};

    switch (type) {
      case MessageType.request:
        if (id == null || op == null) throw const FormatException('Requête sans « id » ou « op »');
      case MessageType.command:
      case MessageType.event:
        if (op == null) throw const FormatException('Message sans « op »');
      case MessageType.response:
        if (id == null || json['ok'] is! bool) {
          throw const FormatException('Réponse sans « id » ou « ok »');
        }
    }

    final errorJson = json['error'];
    return Envelope._(
      v: v,
      type: type,
      id: id,
      op: op,
      data: data,
      ok: json['ok'] as bool?,
      error: errorJson is Map<String, Object?> ? ProtocolError.fromJson(errorJson) : null,
    );
  }
}
