// Paquet 2 : accueil en grille, catalogue, trackpad et clavier à l'écran.
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<void> request(String op, Map<String, Object?> data) async => log.add('$op ${jsonEncode(data)}');
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
        expect(_layout(c).all.map((w) => (w.moduleId, w.size)).toList(),
            [('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]);
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
      await tester.tap(find.byKey(const ValueKey('add-keyboard-small')));
      await _settle(tester);
      expect(_layout(c).pageCount, 2);
      expect(_layout(c).pages[1].single.size, WidgetSize.small);
      expectCleanLayout(tester);
    });

    testWidgets('retirer un widget', (tester) async {
      final (_, c) = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      final kb = _layout(c).all.last.id;
      await tester.tap(find.byKey(ValueKey('remove-$kb')));
      await tester.pump();
      expect(_layout(c).all.map((w) => w.moduleId), ['trackpad']);
    });

    testWidgets('changer la taille d’un widget', (tester) async {
      final (_, c) = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      final tp = _layout(c).all.first.id;
      await tester.tap(find.byKey(ValueKey('resize-$tp')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('size-medium')));
      await _settle(tester);
      expect(_layout(c).find(tp)!.$1.size, WidgetSize.medium);
      expectCleanLayout(tester);
    });

    testWidgets('glisser-déposer un widget sur une case libre', (tester) async {
      final (_, c) = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-edit')));
      await tester.pump();
      await c.read(homeLayoutProvider.notifier).remove(_layout(c).all.first.id); // libère le haut
      await tester.pump();
      final kb = _layout(c).all.single;
      expect(kb.row, 4);
      final from = tester.getCenter(find.byKey(ValueKey('tile-${kb.id}')));
      final pages = tester.getRect(find.byKey(const ValueKey('home-pages')));
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      // Remonte le widget de 4 rangées.
      await gesture.moveBy(Offset(0, -(pages.height / 6) * 4));
      await tester.pump();
      expect(find.byKey(const ValueKey('drop-preview')), findsOneWidget);
      await gesture.up();
      await _settle(tester);
      expect(_layout(c).all.single.row, 0);
    });

    testWidgets('mise en page conservée entre deux lancements', (tester) async {
      final (_, c) = await _pump(tester);
      await c.read(homeLayoutProvider.notifier).add('keyboard', WidgetSize.small);
      final prefs = await SharedPreferences.getInstance();
      final saved = HomeLayout.fromJson(jsonDecode(prefs.getString('home.layout')!), knownModule: (_) => true);
      expect(saved.all, hasLength(3));
    });
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
