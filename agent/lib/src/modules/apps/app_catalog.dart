import 'dart:convert';
import 'dart:io';

import 'package:pegasus_protocol/pegasus_protocol.dart';

/// Application trouvée dans le menu Démarrer.
class InstalledApp {
  const InstalledApp({required this.id, required this.name, required this.path});

  final String id;
  final String name;

  /// Raccourci (.lnk) à ouvrir.
  final String path;

  /// Identifiant stable dérivé du chemin.
  static String idFor(String path) =>
      PegasusCrypto.fingerprint(utf8.encode(path.toLowerCase())).substring(0, 16);
}

/// Application favorite configurée sur l'agent (proposée dans l'app).
class Favorite {
  const Favorite({required this.id, required this.name, required this.path, this.icon});

  final String id;
  final String name;
  final String path;

  /// PNG en base64, ou `null` si l'icône n'a pas pu être extraite.
  final String? icon;

  FavoriteApp toWire() => FavoriteApp(id: id, name: name, icon: icon);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'path': path, 'icon': ?icon};

  static Favorite? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'], path = raw['path'], icon = raw['icon'];
    if (id is! String || name is! String || path is! String) return null;
    return Favorite(id: id, name: name, path: path, icon: icon is String ? icon : null);
  }
}

/// Parcourt les raccourcis du menu Démarrer (tous les utilisateurs + l'utilisateur).
class StartMenuScanner {
  StartMenuScanner([List<Directory>? roots]) : roots = roots ?? defaultRoots();

  final List<Directory> roots;

  static List<Directory> defaultRoots() {
    final env = Platform.environment;
    const sub = r'Microsoft\Windows\Start Menu\Programs';
    return [
      if (env['ProgramData'] != null) Directory('${env['ProgramData']}\\$sub'),
      if (env['APPDATA'] != null) Directory('${env['APPDATA']}\\$sub'),
    ];
  }

  /// Entrées techniques écartées (désinstalleurs, aides, sites web…).
  static final _noise = RegExp(
    r'uninstall|désinstall|desinstall|readme|read me|lisez|help|aide|documentation|website|site web|release notes|license|licence',
    caseSensitive: false,
  );

  Future<List<InstalledApp>> scan() async {
    final byName = <String, InstalledApp>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      // Ordre stable : à nom égal, le raccourci au chemin le plus court gagne.
      final files = <String>[];
      await for (final entity in root.list(recursive: true, followLinks: false).handleError((_) {})) {
        if (entity is File) files.add(entity.path);
      }
      files.sort((a, b) => a.length != b.length ? a.length - b.length : a.compareTo(b));
      for (final path in files) {
        final lower = path.toLowerCase();
        if (!lower.endsWith('.lnk') && !lower.endsWith('.appref-ms')) continue;
        final file = path.split(RegExp(r'[\\/]')).last;
        final name = file.substring(0, file.lastIndexOf('.'));
        if (name.isEmpty || _noise.hasMatch(name)) continue;
        byName.putIfAbsent(name.toLowerCase(), () => InstalledApp(id: InstalledApp.idFor(path), name: name, path: path));
      }
    }
    final apps = byName.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }
}

/// Extrait l'icône d'un raccourci en PNG base64 (via PowerShell / System.Drawing).
class IconExtractor {
  const IconExtractor();

  Future<String?> extract(String path) async {
    if (!Platform.isWindows) return null;
    // Le chemin passe par une variable d'environnement : jamais interprété comme du code.
    const script = r'''
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($env:PEGASUS_ICON_PATH)
$bmp = New-Object System.Drawing.Bitmap 64, 64
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($icon.ToBitmap(), 0, 0, 64, 64)
$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
[Convert]::ToBase64String($ms.ToArray())
''';
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        environment: {'PEGASUS_ICON_PATH': path},
      ).timeout(const Duration(seconds: 15));
      final out = (result.stdout as String).trim();
      if (result.exitCode != 0 || out.isEmpty) return null;
      base64.decode(out); // Vérifie que c'est bien du base64.
      return out;
    } catch (_) {
      return null;
    }
  }
}
