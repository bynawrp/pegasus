import 'dart:convert';
import 'dart:io';

import 'package:pegasus_link/pegasus_link.dart';

import '../modules/apps/app_catalog.dart';

import 'secret_protector.dart';

/// Données persistées de l'agent.
class AgentData {
  const AgentData({required this.identity, required this.devices, this.favorites = const []});
  final AgentIdentity identity;
  final List<PairedDevice> devices;

  /// Applications favorites proposées dans l'app (pas de secret).
  final List<Favorite> favorites;
}

/// Lecture / écriture de `agent.json` ; les secrets sont chiffrés (DPAPI).
class AgentStore {
  AgentStore(this.directory, {SecretProtector? protector})
      : protector = protector ?? SecretProtector.platform();

  final Directory directory;
  final SecretProtector protector;

  File get file => File('${directory.path}${Platform.pathSeparator}agent.json');

  /// Charge les données, ou crée une identité au premier lancement.
  Future<AgentData> loadOrCreate({required String defaultName}) async {
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
        final id = (json['identity'] as Map).cast<String, Object?>();
        final identity = AgentIdentity.fromJson({
          ...id,
          'privateKey': protector.unprotect(id['privateKey'] as String),
        });
        final devices = [
          for (final raw in (json['devices'] as List? ?? const []))
            () {
              final d = (raw as Map).cast<String, Object?>();
              return PairedDevice.fromJson({...d, 'secret': protector.unprotect(d['secret'] as String)});
            }(),
        ];
        final favorites = [
          for (final raw in (json['favorites'] as List? ?? const []))
            ?Favorite.fromJson(raw),
        ];
        return AgentData(identity: identity, devices: devices, favorites: favorites);
      } catch (_) {
        // Fichier corrompu ou illisible (autre session Windows) : on le
        // met de côté et on repart d'une identité neuve.
        await file.rename('${file.path}.bak-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    final data = AgentData(identity: AgentIdentity.generate(name: defaultName), devices: const []);
    await save(data);
    return data;
  }

  Future<void> save(AgentData data) async {
    await directory.create(recursive: true);
    final json = {
      'version': 1,
      'identity': {
        ...data.identity.toJson(),
        'privateKey': protector.protect(data.identity.privateKeyPem),
      },
      'devices': [
        for (final d in data.devices) {...d.toJson(), 'secret': protector.protect(d.secret)},
      ],
      'favorites': [for (final f in data.favorites) f.toJson()],
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(json), flush: true);
    await tmp.rename(file.path);
  }
}
