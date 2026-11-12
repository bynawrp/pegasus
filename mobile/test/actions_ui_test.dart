// Paquet 3 : Lecture, Alimentation, Favoris, Ouvrir un lien (écrans + widgets).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/main.dart';
import 'package:pegasus/src/core/local_network.dart';
import 'package:pegasus/src/core/providers.dart';
import 'package:pegasus/src/core/secure_store.dart';
import 'package:pegasus/src/core/share_intake.dart';
import 'package:pegasus/src/home/home_layout_provider.dart';
import 'package:pegasus/src/modules/favorites/favorites_module.dart';
import 'package:pegasus/src/modules/input/input_service.dart';
import 'package:pegasus/src/modules/keyboard/keyboard_module.dart';
import 'package:pegasus/src/modules/link/link_module.dart';
import 'package:pegasus/src/modules/media/media_module.dart';
import 'package:pegasus/src/modules/power/power_module.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';
import 'package:pegasus_ui/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phones = {
  'iPhone SE': Size(320, 568),
  'Android compact': Size(360, 640),
  'iPhone 15': Size(393, 852),
  'Grand Android': Size(430, 932),
};

const _pc = PairedAgent(
  agentId: 'a1', agentName: 'PC-BUREAU', host: '192.168.1.20', port: 47800,
  fingerprint: 'fp', deviceId: 'd1', deviceSecret: 's',
);

LinkState _connected({Map<String, bool> modules = const {'media': true, 'power': true, 'apps': true}}) => LinkState(
      LinkStatus.connected,
      info: SessionInfo(agentId: 'a1', agentName: 'PC', agentVersion: '0.3.0', os: 'windows', modules: modules, paused: false),
    );

class _FixedLink extends LinkStateNotifier {
  _FixedLink(this.fixed);
  final LinkState fixed;
  @override
  LinkState build() => fixed;
}

class _FixedPc extends PairedPcNotifier {
  _FixedPc(this.pc);
  final PairedAgent? pc;
  @override
  Future<PairedAgent?> build() async => pc;
}

class _Network implements LocalNetworkPermission {
  @override
  Future<bool> request() async => true;
  @override
  Future<void> openSettings() async {}
}

class _Links implements IncomingLinks {
  final controller = StreamController<String>.broadcast();
  @override
  Stream<String> get urls => controller.stream;
}

/// Faux agent : journalise les requêtes, répond, pousse des évènements.
class _Agent implements RemoteSender {
  final log = <String>[];
  final events$ = StreamController<Envelope>.broadcast();
  AudioState audio = const AudioState(volume: 42, muted: false);
  List<FavoriteApp> apps = const [
    FavoriteApp(id: 'steam', name: 'Steam'),
    FavoriteApp(id: 'discord', name: 'Discord avec un nom très long'),
  ];
  ErrorCode? failWith;

  @override
  void command(String op, Map<String, Object?> data) => log.add('$op ${jsonEncode(data)}');

  /// Contrat : chaque requête de l'app doit passer la validation de l'agent.
  void _validate(String op, Map<String, Object?> data) {
    final power = PowerAction.fromOp(op);
    if (power != null) return checkPowerConfirmation(power, data);
    switch (op) {
      case 'audio.set':
        parseAudioSet(data);
      case 'apps.launch':
        parseAppId(data);
      case 'url.open':
        parseUrl(data);
      case 'audio.get' || 'apps.list' || 'media.play_pause' || 'media.next' || 'media.previous':
        break;
      default:
        fail('Opération inattendue : $op');
    }
  }

  @override
  Future<Map<String, Object?>> request(String op, Map<String, Object?> data) async {
    _validate(op, data);
    if (op != 'audio.get' && op != 'apps.list') log.add('$op ${jsonEncode(data)}');
    final fail = failWith;
    if (fail != null && op != 'audio.get' && op != 'apps.list') {
      throw RequestFailedException(op, ProtocolError(fail, 'Refusé par le PC'));
    }
    switch (op) {
      case 'audio.get':
        return audio.toJson();
      case 'audio.set':
        final req = parseAudioSet(data);
        audio = AudioState(volume: req.volume ?? audio.volume, muted: req.muted ?? audio.muted);
        return audio.toJson();
      case 'apps.list':
        return {'apps': [for (final a in apps) a.toJson()]};
    }
    return const {};
  }

  @override
  Stream<Envelope> get events => events$.stream;
}

Future<(_Agent, ProviderContainer, _Links)> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  LinkState? link,
  Widget? home,
  PairedAgent? pc = _pc,
  double textScale = 1,
}) async {
  setScreenSize(tester, size);
  final agent = _Agent();
  final links = _Links();
  final container = ProviderContainer(overrides: [
    secureStoreProvider.overrideWithValue(MemorySecureStore()),
    deviceNameProvider.overrideWith((ref) async => 'Test'),
    networkChangesProvider.overrideWithValue(const Stream.empty()),
    localNetworkPermissionProvider.overrideWithValue(_Network()),
    pairedPcProvider.overrideWith(() => _FixedPc(pc)),
    linkStateProvider.overrideWith(() => _FixedLink(link ?? _connected())),
    remoteSenderProvider.overrideWithValue(agent),
    incomingLinksProvider.overrideWithValue(links),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: withTextScale(textScale, home == null ? const PegasusApp() : MaterialApp(theme: PegasusTheme.build(), home: Scaffold(body: home))),
  ));
  await tester.pump();
  await tester.pump();
  return (agent, container, links);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadPegasusFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('zéro overflow', () {
    for (final MapEntry(key: phone, value: size) in _phones.entries) {
      testWidgets('page 2 de l’accueil (lecture, alimentation, favoris, lien) · $phone', (tester) async {
        final (_, c, _) = await _pump(tester, size: size);
        expect(c.read(homeLayoutProvider).value!.pageCount, 2);
        // Glisser hors du trackpad (sur le widget clavier), qui garde ses gestes.
        await tester.flingFrom(tester.getCenter(find.byType(KeyboardShortcutsPad)), const Offset(-400, 0), 1500);
        await _settle(tester);
        expect(find.byType(MediaPad), findsOneWidget);
        expect(find.byType(PowerPad), findsOneWidget);
        expect(find.byType(FavoritesGrid), findsOneWidget);
        expectCleanLayout(tester);
      });

      for (final MapEntry(key: name, value: screen) in {
        'Lecture': const MediaScreen(),
        'Alimentation': const PowerScreen(),
        'Favoris': const FavoritesScreen(),
        'Lien': const LinkScreen(),
      }.entries) {
        testWidgets('écran $name · $phone', (tester) async {
          await _pump(tester, size: size, home: screen);
          await _settle(tester);
          expectCleanLayout(tester);
        });
      }
    }

    testWidgets('écran Lien, clavier ouvert, texte ×1.3 · iPhone SE', (tester) async {
      await _pump(tester, size: const Size(320, 568), home: const LinkScreen(), textScale: 1.3);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expectCleanLayout(tester);
    });
  });

  group('Lecture', () {
    testWidgets('volume du PC affiché, curseur → audio.set regroupé, muet', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const MediaPad());
      await _settle(tester);
      expect(find.text('42'), findsOneWidget);
      await tester.drag(find.byKey(const ValueKey('media-volume')), const Offset(-500, 0));
      await tester.pump(const Duration(milliseconds: 200));
      final sets = agent.log.where((l) => l.startsWith('audio.set')).toList();
      expect(sets, isNotEmpty);
      expect(sets.length, lessThan(5), reason: 'envois regroupés pendant le glisser');
      expect(sets.last, 'audio.set {"volume":0}');
      await tester.tap(find.byKey(const ValueKey('media-mute')));
      await tester.pump();
      expect(agent.log.last, 'audio.set {"muted":true}');
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    });

    testWidgets('volume changé sur le PC → curseur mis à jour', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const MediaPad());
      await _settle(tester);
      agent.events$.add(Envelope.event('audio.changed', {'volume': 77, 'muted': false}));
      await tester.pump();
      await tester.pump();
      expect(find.text('77'), findsOneWidget);
    });

    testWidgets('lecture / pause, suivant, précédent', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const MediaPad());
      await tester.tap(find.byKey(const ValueKey('media-play')));
      await tester.tap(find.byKey(const ValueKey('media-next')));
      await tester.tap(find.byKey(const ValueKey('media-previous')));
      await tester.pump();
      expect(agent.log, ['media.play_pause {}', 'media.next {}', 'media.previous {}']);
    });

    testWidgets('module désactivé sur le PC → grisé, rien envoyé', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const MediaPad(), link: _connected(modules: {'media': false}));
      expect(find.text('Désactivé sur le PC'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-play')), warnIfMissed: false);
      expect(agent.log, isEmpty);
    });
  });

  group('Alimentation', () {
    testWidgets('verrouiller : immédiat, retour d’état', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const PowerScreen());
      await tester.tap(find.byKey(const ValueKey('power-lock')));
      await tester.pump();
      await tester.pump();
      expect(agent.log, ['power.lock {}']);
      expect(find.text('PC verrouillé'), findsOneWidget);
    });

    testWidgets('éteindre : confirmation obligatoire, annuler = rien', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const PowerScreen());
      await tester.tap(find.byKey(const ValueKey('power-shutdown')));
      await tester.pumpAndSettle();
      expect(find.text('ÉTEINDRE ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(agent.log, isEmpty);
      await tester.tap(find.byKey(const ValueKey('power-shutdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-power')));
      await tester.pumpAndSettle();
      expect(agent.log, ['power.shutdown {"confirmed":true}']);
      expect(find.text('Le PC s’éteint'), findsOneWidget);
    });

    testWidgets('refus du PC → message d’erreur', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const PowerScreen());
      agent.failWith = ErrorCode.rejected;
      await tester.tap(find.byKey(const ValueKey('power-sleep')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Refusé par le PC'), findsOneWidget);
    });
  });

  group('Favoris', () {
    testWidgets('liste du PC, lancement en un tap', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const FavoritesGrid());
      await _settle(tester);
      expect(find.byKey(const ValueKey('fav-steam')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-steam')));
      await tester.pump();
      await tester.pump();
      expect(agent.log, ['apps.launch {"id":"steam"}']);
      expect(find.text('Steam lancé'), findsOneWidget);
      expectCleanLayout(tester);
    });

    testWidgets('aucun favori → explication', (tester) async {
      final (agent, c, _) = await _pump(tester, home: const FavoritesGrid());
      agent.apps = const [];
      c.invalidate(favoriteAppsProvider);
      await _settle(tester);
      expect(find.byKey(const ValueKey('fav-empty')), findsOneWidget);
    });

    testWidgets('beaucoup de favoris : pages sans débordement', (tester) async {
      final (agent, c, _) = await _pump(tester, size: const Size(320, 568), home: const SizedBox.shrink());
      agent.apps = [for (var i = 0; i < 40; i++) FavoriteApp(id: 'a$i', name: 'Application $i')];
      c.invalidate(favoriteAppsProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: PegasusTheme.build(), home: const FavoritesScreen()),
      ));
      await _settle(tester);
      expect(find.byKey(const ValueKey('fav-a0')), findsOneWidget);
      expectCleanLayout(tester);
    });
  });

  group('Ouvrir un lien', () {
    testWidgets('lien valide → url.open ; domaine seul complété en https', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const LinkScreen());
      await tester.enterText(find.byKey(const ValueKey('link-url')), 'exemple.fr/page');
      await tester.tap(find.byKey(const ValueKey('link-send')));
      await tester.pump();
      await tester.pump();
      expect(agent.log, ['url.open {"url":"https://exemple.fr/page"}']);
    });

    testWidgets('lien refusé (ftp, javascript) → erreur, rien envoyé', (tester) async {
      final (agent, _, _) = await _pump(tester, home: const LinkScreen());
      for (final bad in ['ftp://exemple.fr', 'javascript:alert(1)']) {
        await tester.enterText(find.byKey(const ValueKey('link-url')), bad);
        await tester.tap(find.byKey(const ValueKey('link-send')));
        await tester.pump();
        expect(find.textContaining('http'), findsWidgets, reason: bad);
      }
      expect(agent.log, isEmpty);
      expectCleanLayout(tester);
    });

    testWidgets('lien partagé vers Pegasus → écran prérempli', (tester) async {
      final (agent, _, links) = await _pump(tester);
      links.controller.add('https://youtu.be/abc');
      await tester.pumpAndSettle();
      expect(find.byType(LinkScreen), findsOneWidget);
      expect(find.text('https://youtu.be/abc'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('link-send')));
      await tester.pumpAndSettle();
      expect(agent.log, ['url.open {"url":"https://youtu.be/abc"}']);
      expect(find.byType(LinkScreen), findsNothing, reason: 'fermé après envoi');
    });

    testWidgets('lien partagé sans PC associé → message', (tester) async {
      final (_, _, links) = await _pump(tester, pc: null);
      links.controller.add('https://youtu.be/abc');
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinkScreen), findsNothing);
      expect(find.textContaining('Associez d’abord'), findsOneWidget);
    });
  });
}
