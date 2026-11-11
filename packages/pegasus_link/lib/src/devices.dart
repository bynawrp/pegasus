/// Appareil associé à l'agent (spec §3).
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.secret,
    required this.pairedAt,
    this.model = '',
    this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final String model;

  /// Secret partagé (base64url), ne quitte jamais l'agent après l'appairage.
  final String secret;
  final DateTime pairedAt;
  final DateTime? lastSeen;

  PairedDevice copyWith({String? name, DateTime? lastSeen}) => PairedDevice(
        id: id,
        name: name ?? this.name,
        platform: platform,
        model: model,
        secret: secret,
        pairedAt: pairedAt,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'model': model,
        'secret': secret,
        'pairedAt': pairedAt.toIso8601String(),
        if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, Object?> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        platform: json['platform'] as String? ?? '',
        model: json['model'] as String? ?? '',
        secret: json['secret'] as String,
        pairedAt: DateTime.parse(json['pairedAt'] as String),
        lastSeen: json['lastSeen'] == null ? null : DateTime.parse(json['lastSeen'] as String),
      );
}
