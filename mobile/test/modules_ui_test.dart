// Paquet 2 : accueil en grille, catalogue, trackpad et clavier à l'écran.
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus/main.dart';
import 'package:pegasus/src/core/local_network.dart';
import 'package:pegasus/src/core/providers.dart';
import 'package:pegasus/src/core/secure_store.dart';
import 'package:pegasus/src/home/home_layout.dart';
import 'package:pegasus/src/home/home_layout_provider.dart';
import 'package:pegasus/src/modules/input/input_service.dart';
import 'package:pegasus/src/modules/keyboard/keyboard_module.dart';
import 'package:pegasus/src/modules/trackpad/trackpad_module.dart';
import 'package:pegasus_link/pegasus_link.dart';
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
  agentId: 'a1',
  agentName: 'PC-BUREAU',
  host: '192.168.1.20',
  port: 47800,
  fingerprint: 'fp',
  deviceId: 'd1',
  deviceSecret: 's',
);

LinkState _connected({bool paused = false, bool input = true}) => LinkState(
      LinkStatus.connected,
      info: SessionInfo(
        agentId: 'a1',
        agentName: 'PC',
        agentVersion: '0.2.0',
        os: 'windows',
        modules: {'input': input},
        paused: paused,
      ),
    );

class _FixedLink extends LinkStateNotifier {
  _FixedLink(this.fixed);
  final LinkState fixed;

  @override
  LinkState build() => fixed;
}

class _FixedPc extends PairedPcNotifier {
  @override
  Future<PairedAgent?> build() async => _pc;
}

class _Network implements LocalNetworkPermission {
  @override
  Future<bool> request() async => true;
  @override
  Future<void> openSettings() async {}
}

class _Sender implements RemoteSender {
  final log = <String>[];

  @override
  void command(String op, Map<String, Object?> data) => log.add('$op ${jsonEncode(data)}');

  @override
  Future<Map<String, Object?>> request(String op, Map<String, Object?> data) async {
    log.add('$op ${jsonEncode(data)}');
    return const {};
  }

  @override
  Stream<Envelope> get events => const Stream.empty();
}

Future<(_Sender, ProviderContainer)> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  LinkState? link,
  Widget? home,
  double textScale = 1,
}) async {
  setScreenSize(tester, size);
  final sender = _Sender();
  final container = ProviderContainer(overrides: [
    secureStoreProvider.overrideWithValue(MemorySecureStore()),
    deviceNameProvider.overrideWith((ref) async => 'Test'),
    networkChangesProvider.overrideWithValue(const Stream.empty()),
    localNetworkPermissionProvider.overrideWithValue(_Network()),
    pairedPcProvider.overrideWith(_FixedPc.new),
    linkStateProvider.overrideWith(() => _FixedLink(link ?? _connected())),
    remoteSenderProvider.overrideWithValue(sender),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: withTextScale(
      textScale,
      home == null ? const PegasusApp() : MaterialApp(theme: PegasusTheme.build(), home: home),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return (sender, container);
}

/// Le mode édition anime les widgets en boucle : pumpAndSettle ne finirait jamais.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

HomeLayout _layout(ProviderContainer c) => c.read(homeLayoutProvider).value!;

void main() {
  setUpAll(loadPegasusFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Accueil en grille', () {
    for (final MapEntry(key: phone, value: size) in _phones.entries) {
      testWidgets('par défaut : trackpad 4×4 + clavier 4×2, zéro overflow · $phone', (tester) async {
        final (_, c) = await _pump(tester, size: size);
        expect(_layout(c).pages[0].map((w) => (w.moduleId, w.size)).toList(),
            [('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]);
        expect(_layout(c).pages[1].map((w) => w.moduleId).toList(), ['media', 'power', 'favorites', 'link']);
        expect(find.byKey(const ValueKey('trackpad-surface')), findsOneWidget);
        expect(find.byType(KeyboardShortcutsPad), findsOneWidget);
        expect(find.byType(Scrollable), findsWidgets); // PageView uniquement (horizontal, paginé)
        expectCleanLayout(tester);
      });

      testWidgets('mode édition + galerie + texte ×1.3 · $phone', (tester) async {
        await _pump(tester, size: size, textScale: phone == 'iPhone SE' ? 1.3 : 1);
        await tester.tap(find.byKey(const ValueKey('home-edit')));
        await tester.pump();
        expect(find.byKey(const ValueKey('home-done')), findsOneWidget);
        expectCleanLayout(tester);
        await tester.tap(find.byKey(const ValueKey('home-add')));
        await _settle(tester);
        expectCleanLayout(tester);
      });
    }

    testWidgets('ajouter : page pleine → nouvelle page, points de pagination', (tester) async {
      final (_, c) = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-add')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('gallery-keyboard')));
      await _settle(tester);
      expectCleanLayout(tester);
      await tester.tap(find.byKey(const ValueKey('add-keyboard-small')));
      await _settle(tester);
      expect(_layout(c).pageCount, 2, reason: 'page 1 pleine → posé en page 2');
      expect(_layout(c).pages[1].last.moduleId, 'keyboard');
      expect(_layout(c).pages[1].last.size, WidgetSize.small);
      expectCleanLayout(tester);
    });

    testWidgets('retirer un widget', (tester) async {
      final (_, c) = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      final kb = _layout(c).pages[0].last.id;
      await tester.tap(find.byKey(ValueKey('remove-$kb')));
      await tester.pump();
      expect(_layout(c).pages[0].map((w) => w.moduleId), ['trackpad']);
    });

    testWidgets('changer la taille d’un widget', (tester) async {
      final (_, c) = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      final tp = _layout(c).pages[0].first.id;
      await tester.tap(find.byKey(ValueKey('resize-$tp')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('size-medium')));
      await _settle(tester);
      expect(_layout(c).find(tp)!.$1.size, WidgetSize.medium);
      expectCleanLayout(tester);
    });

    Future<void> dragTile(WidgetTester tester, String id, Offset by) async {
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tile-$id'))));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('drag-floating')), findsOneWidget);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveBy(by / 8);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('drop-preview')), findsOneWidget);
      await gesture.up();
      await _settle(tester);
    }

    testWidgets('façon iOS : déposer le clavier sur le trackpad le pousse dessous', (tester) async {
      final (_, c) = await _pump(tester);
      final tp = _layout(c).pages[0].first.id;
      final kb = _layout(c).pages[0].last.id;
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      final pages = tester.getRect(find.byKey(const ValueKey('home-pages')));
      // Le clavier (rangées 4-5) remonte tout en haut, sur le trackpad.
      await dragTile(tester, kb, Offset(0, -(pages.height / 6) * 4));
      final l = _layout(c);
      expect(l.pages[0].map((w) => w.id).toList(), [kb, tp]);
      expect(l.find(kb)!.$1.row, 0);
      expect(l.find(tp)!.$1.row, 2);
      expectCleanLayout(tester);
    });

    testWidgets('aperçu en direct : les autres widgets se déplacent pendant le glisser', (tester) async {
      final (_, c) = await _pump(tester);
      final tp = _layout(c).pages[0].first.id;
      final kb = _layout(c).pages[0].last.id;
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      final pages = tester.getRect(find.byKey(const ValueKey('home-pages')));
      final before = tester.getRect(find.byKey(ValueKey('tile-$tp'))).top;
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('tile-$kb'))));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(0, -(pages.height / 6) * 4 / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _settle(tester);
      // Doigt toujours posé : le trackpad est déjà descendu, rien n'est encore enregistré.
      expect(tester.getRect(find.byKey(ValueKey('tile-$tp'))).top, greaterThan(before + 10));
      expect(_layout(c).pages[0].first.id, tp);
      await gesture.up();
      await _settle(tester);
      expect(_layout(c).pages[0].first.id, kb);
    });

    testWidgets('mise en page conservée entre deux lancements', (tester) async {
      final (_, c) = await _pump(tester);
      await c.read(homeLayoutProvider.notifier).add('keyboard', WidgetSize.small);
      final prefs = await SharedPreferences.getInstance();
      final saved = HomeLayout.fromJson(jsonDecode(prefs.getString('home.layout')!), knownModule: (_) => true);
      expect(saved.all, hasLength(7));
    });
  });

  testWidgets('glisser sur le trackpad de l’accueil ne change pas de page', (tester) async {
    final (sender, c) = await _pump(tester);
    expect(_layout(c).pageCount, 2);
    final surface = find.byKey(const ValueKey('trackpad-surface'));
    final g = await tester.startGesture(tester.getCenter(surface));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<PageView>(find.byKey(const ValueKey('home-pages'))).controller!.page, 0);
    expect(sender.log.where((l) => l.startsWith('input.move')), isNotEmpty);
    // Hors du trackpad (sur le widget clavier), le glissement change bien de page.
    await tester.flingFrom(tester.getCenter(find.byType(KeyboardShortcutsPad)), const Offset(-300, 0), 1500);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<PageView>(find.byKey(const ValueKey('home-pages'))).controller!.page, 1);
  });

  group('Catalogue des modules', () {
    for (final MapEntry(key: phone, value: size) in _phones.entries) {
      testWidgets('pages sans overflow · $phone', (tester) async {
        await _pump(tester, size: size);
        await tester.tap(find.byKey(const ValueKey('tab-modules')));
        await tester.pump();
        expect(find.byKey(const ValueKey('module-trackpad')), findsOneWidget);
        expectCleanLayout(tester);
      });
    }

    testWidgets('module disponible → ouvre l’écran ; à venir → message', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('tab-modules')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('module-gamepad')).hitTestable().first, warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('module-keyboard')));
      await tester.pumpAndSettle();
      expect(find.byType(KeyboardScreen), findsOneWidget);
    });
  });

  group('Trackpad', () {
    testWidgets('tap → clic gauche ; glisser → déplacement groupé', (tester) async {
      final (sender, _) = await _pump(tester, home: const TrackpadScreen());
      final surface = find.byKey(const ValueKey('trackpad-surface'));
      await tester.tap(surface);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sender.log, ['input.click {"button":"left","count":1}']);

      final g = await tester.startGesture(tester.getCenter(surface));
      for (var i = 0; i < 5; i++) {
        await g.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 5));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 40));
      final moves = sender.log.where((l) => l.startsWith('input.move')).toList();
      expect(moves, isNotEmpty);
      expect(moves.length, lessThan(5), reason: 'mouvements regroupés');
    });

    testWidgets('tap à deux doigts → clic droit', (tester) async {
      final (sender, _) = await _pump(tester, home: const TrackpadScreen());
      final center = tester.getCenter(find.byKey(const ValueKey('trackpad-surface')));
      final a = await tester.startGesture(center - const Offset(30, 0), pointer: 1);
      final b = await tester.startGesture(center + const Offset(30, 0), pointer: 2);
      await tester.pump(const Duration(milliseconds: 60));
      await a.up();
      await b.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(sender.log, contains('input.click {"button":"right","count":1}'));
    });

    testWidgets('boutons physiques : appui = enfoncé, relâche = relevé', (tester) async {
      final (sender, _) = await _pump(tester, home: const TrackpadScreen());
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('trackpad-left'))));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(sender.log, [
        'input.button {"button":"left","state":"down"}',
        'input.button {"button":"left","state":"up"}',
      ]);
    });

    testWidgets('boutons en icônes de souris, réglage de vitesse conservé', (tester) async {
      await _pump(tester, home: const TrackpadScreen());
      expect(find.text('Gauche'), findsNothing);
      expect(find.bySemanticsLabel('Clic gauche'), findsOneWidget);
      expect(find.bySemanticsLabel('Clic droit'), findsOneWidget);
      await tester.drag(find.byKey(const ValueKey('trackpad-speed')), const Offset(200, 0));
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('trackpad.speed'), greaterThan(1.0));
    });

    for (final MapEntry(key: name, value: link) in {
      'PC non connecté': const LinkState(LinkStatus.waiting, retryIn: Duration(seconds: 4)),
      'En pause sur le PC': _connected(paused: true),
      'Désactivé sur le PC': _connected(input: false),
    }.entries) {
      testWidgets('bloqué si « $name » : rien n’est envoyé', (tester) async {
        final (sender, _) = await _pump(tester, home: const TrackpadScreen(), link: link);
        expect(find.text(name), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('trackpad-surface')), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 50));
        expect(sender.log, isEmpty);
        expectCleanLayout(tester);
      });
    }

    for (final MapEntry(key: phone, value: size) in _phones.entries) {
      testWidgets('écran plein sans overflow · $phone', (tester) async {
        await _pump(tester, size: size, home: const TrackpadScreen());
        expectCleanLayout(tester);
      });
    }
  });

  group('Clavier', () {
    testWidgets('frappe en direct, retour arrière, Entrée', (tester) async {
      final (sender, _) = await _pump(tester, home: const KeyboardScreen());
      final field = find.byKey(const ValueKey('keyboard-input'));
      await tester.enterText(field, 'Salut');
      await tester.pump();
      await tester.enterText(field, 'Sal');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(sender.log, [
        'input.text {"text":"Salut"}',
        'input.key {"key":"backspace","modifiers":[],"repeat":2}',
        'input.key {"key":"enter","modifiers":[]}',
      ]);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    });

    testWidgets('Ctrl puis « s » → raccourci Ctrl+S, pas de texte', (tester) async {
      final (sender, _) = await _pump(tester, home: const KeyboardScreen());
      await tester.tap(find.byKey(const ValueKey('mod-ctrl')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('keyboard-input')), 's');
      await tester.pump();
      expect(sender.log, ['input.key {"key":"s","modifiers":["ctrl"]}']);
    });

    testWidgets('touches spéciales et raccourcis', (tester) async {
      final (sender, _) = await _pump(tester, home: const KeyboardScreen());
      await tester.tap(find.byKey(const ValueKey('key-Échap')));
      await tester.tap(find.byKey(const ValueKey('key-Alt+Tab')));
      await tester.pump();
      expect(sender.log, [
        'input.key {"key":"escape","modifiers":[]}',
        'input.key {"key":"tab","modifiers":["alt"]}',
      ]);
    });

    for (final MapEntry(key: phone, value: size) in _phones.entries) {
      testWidgets('écran plein, clavier système ouvert · $phone', (tester) async {
        await _pump(tester, size: size, home: const KeyboardScreen());
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        expectCleanLayout(tester);
      });
    }

    testWidgets('écran plein, clavier ouvert, texte ×1.3 · iPhone SE', (tester) async {
      await _pump(tester, size: const Size(320, 568), home: const KeyboardScreen(), textScale: 1.3);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expectCleanLayout(tester);
    });
  });
}
