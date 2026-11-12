import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

/// Lien à ouvrir sur le PC à partir d'un partage ou d'un lien Pegasus :
/// - `pegasus://open?url=https://…` (raccourci iOS, autre app) ;
/// - texte partagé contenant un lien (Android : Partager → Pegasus).
String? incomingUrl({Uri? link, String? sharedText}) {
  if (link != null) {
    if (link.scheme != 'pegasus' || link.host != 'open') return null;
    final url = link.queryParameters['url'];
    return url == null ? null : extractUrl(url) ?? url;
  }
  if (sharedText != null) return extractUrl(sharedText);
  return null;
}

/// Source des liens entrants (remplacée dans les tests).
abstract class IncomingLinks {
  Stream<String> get urls;
}

class PlatformIncomingLinks implements IncomingLinks {
  static const _share = MethodChannel('pegasus/share');

  @override
  Stream<String> get urls {
    final controller = StreamController<String>();
    void emit(String? url) {
      if (url != null && !controller.isClosed) controller.add(url);
    }

    final appLinks = AppLinks();
    final sub = appLinks.uriLinkStream.listen((uri) => emit(incomingUrl(link: uri)), onError: (_) {});
    _share.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') emit(incomingUrl(sharedText: call.arguments as String?));
    });
    _share.invokeMethod<String>('initialText').then(
          (text) => emit(incomingUrl(sharedText: text)),
          onError: (_) {}, // iOS : pas de canal de partage (raccourci + lien pegasus://).
        );
    controller.onCancel = () {
      sub.cancel();
      _share.setMethodCallHandler(null);
    };
    return controller.stream;
  }
}

final incomingLinksProvider = Provider<IncomingLinks>((ref) => PlatformIncomingLinks());
