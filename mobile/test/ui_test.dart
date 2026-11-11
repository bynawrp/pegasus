// Tests d'interface de l'app : zéro overflow sur petits et grands téléphones,
// texte agrandi, clavier ouvert ; parcours d'appairage à l'écran.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/main.dart';
import 'package:pegasus/src/core/pairing_service.dart';
import 'package:pegasus/src/core/providers.dart';
import 'package:pegasus/src/core/secure_store.dart';
import 'package:pegasus/src/pairing/manual_pair_screen.dart';
import 'package:pegasus/src/pairing/scan_screen.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_ui/pegasus_ui.dart';
import 'package:pegasus_ui/testing.dart';

const _phones = {
  'iPhone SE (320×568)': Size(320, 568),
  'Android compact (360×640)': Size(360, 640),
  'iPhone 15 (393×852)': Size(393, 852),
  'Grand Android (430×932)': Size(430, 932),
};

const _pc = PairedAgent(
  agentId: 'a1',
  agentName: 'PC-BUREAU-GAMING-AVEC-UN-NOM-TRES-LONG',
  host: '192.168.100.200',
  port: 47800,
  fingerprint: 'Zx9_aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5',
  deviceId: 'd1',
  deviceSecret: 's',
);

const _info = SessionInfo(
  agentId: 'a1',
  agentName: 'PC',
  agentVersion: '0.1.0',
  os: 'windows',
  modules: {'input': true},
  paused: false,
);

final _linkStates = <String, LinkState>{
  'connecté': const LinkState(LinkStatus.connected, info: _info),
  'en pause': LinkState(LinkStatus.connected, info: _info.copyWith(paused: true)),
  'connexion': const LinkState(LinkStatus.connecting),
  'nouvel essai': const LinkState(LinkStatus.waiting, retryIn: Duration(seconds: 16)),
  'non autorisé': const LinkState(LinkStatus.unauthorized),
  'certificat inattendu': const LinkState(LinkStatus.untrusted),
  'remplacé': const LinkState(LinkStatus.replaced),
};

class _FixedLink extends LinkStateNotifier {
  _FixedLink(this.fixed);
  final LinkState fixed;
  int reconnects = 0;

  @override
  LinkState build() => fixed;

  @override
  void reconnect() => reconnects++;
}

class _FakePairing extends PairingService {
  _FakePairing(super.ref);
  final calls = <String>[];
  String fingerprint = 'ABCDEFGH-rest-of-fingerprint';
  PairingFailure? fail;

  @override
  Future<PairedAgent> pairWithQr(String raw) async {
    calls.add('qr:$raw');
    if (fail != null) throw fail!;
    return _pc;
  }

  @override
  Future<String> probe(String host, int port) async {
    calls.add('probe:$host:$port');
    if (fail != null) throw fail!;
    return fingerprint;
  }

  @override
  Future<PairedAgent> pairWithCode({
    required String host,
    required int port,
    required String fingerprint,
    required String code,
  }) async {
    calls.add('code:$host:$port:$fingerprint:$code');
    return _pc;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Size size,
  PairedAgent? pc,
  LinkState? link,
  double textScale = 1,
  Widget? home,
  _FakePairing Function(Ref)? pairing,
}) async {
  setScreenSize(tester, size);
  final store = MemorySecureStore();
  final container = ProviderContainer(overrides: [
    secureStoreProvider.overrideWithValue(store),
    deviceNameProvider.overrideWith((ref) async => 'Test'),
    networkChangesProvider.overrideWithValue(const Stream.empty()),
    pairedPcProvider.overrideWith(() => _FixedPc(pc)),
    if (link != null) linkStateProvider.overrideWith(() => _FixedLink(link)),
    if (pairing != null) pairingServiceProvider.overrideWith(pairing),
    qrScannerProvider.overrideWithValue(
      (context, onCode) => GestureDetector(
        key: const ValueKey('fake-camera'),
        onTap: () => onCode('pegasus://pair?v=1&h=1.2.3.4&p=47800&id=a&n=PC&fp=f&t=t'),
        child: const ColoredBox(color: Colors.black),
      ),
    ),
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
  return container;
}

class _FixedPc extends PairedPcNotifier {
  _FixedPc(this.pc);
  PairedAgent? pc;

  @override
  Future<PairedAgent?> build() async => pc;

  @override
  Future<void> save(PairedAgent pc) async => state = AsyncData(this.pc = pc);

  @override
  Future<void> forget() async => state = AsyncData(pc = null);
}

void main() {
  setUpAll(loadPegasusFonts);

  group('zéro overflow', () {
    for (final MapEntry(key: phone, value: size) in _phones.entries) {
      testWidgets('accueil sans PC · $phone', (tester) async {
        await _pump(tester, size: size);
        expect(find.byKey(const ValueKey('scan-qr')), findsOneWidget);
        expectCleanLayout(tester);
      });

      testWidgets('scan · $phone', (tester) async {
        await _pump(tester, size: size, home: const ScanScreen());
        expectCleanLayout(tester);
      });

      testWidgets('code manuel, clavier ouvert · $phone', (tester) async {
        await _pump(tester, size: size, home: const ManualPairScreen());
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        expectCleanLayout(tester);
        // Code complet → validation automatique → erreur d'adresse affichée.
        await tester.enterText(find.byKey(const ValueKey('host')), '192.168');
        await tester.enterText(find.byKey(const ValueKey('code')), '482193');
        await tester.pump();
        expect(find.byKey(const ValueKey('pair-error')), findsOneWidget);
        expectCleanLayout(tester);
      });

      for (final MapEntry(key: name, value: link) in _linkStates.entries) {
        testWidgets('app · $name · $phone', (tester) async {
          await _pump(tester, size: size, pc: _pc, link: link);
          for (final tab in ['tab-home', 'tab-modules', 'tab-pc']) {
            await tester.tap(find.byKey(ValueKey(tab)));
            await tester.pump();
            expectCleanLayout(tester);
          }
        });
      }
    }

    testWidgets('texte agrandi ×1.3 · iPhone SE · tous les écrans', (tester) async {
      await _pump(tester, size: const Size(320, 568), pc: _pc, link: _linkStates['nouvel essai'], textScale: 1.3);
      for (final tab in ['tab-home', 'tab-modules', 'tab-pc']) {
        await tester.tap(find.byKey(ValueKey(tab)));
        await tester.pump();
        expectCleanLayout(tester);
      }
    });

    testWidgets('texte agrandi ×1.3 · iPhone SE · code manuel clavier ouvert + erreur', (tester) async {
      await _pump(tester, size: const Size(320, 568), home: const ManualPairScreen(), textScale: 1.3);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('host')), '192.168');
      await tester.enterText(find.byKey(const ValueKey('code')), '482193');
      await tester.pump();
      expect(find.byKey(const ValueKey('pair-error')), findsOneWidget);
      expectCleanLayout(tester);
    });

    testWidgets('texte agrandi ×1.3 · iPhone SE · association', (tester) async {
      await _pump(tester, size: const Size(320, 568), textScale: 1.3);
      expectCleanLayout(tester);
      await tester.tap(find.byKey(const ValueKey('manual-pair')));
      await tester.pumpAndSettle();
      expectCleanLayout(tester);
    });
  });

  group('parcours', () {
    testWidgets('scan d’un QR → appairage → app ouverte', (tester) async {
      late _FakePairing fake;
      final container = await _pump(tester,
          size: const Size(393, 852),
          link: _linkStates['connecté'],
          pairing: (ref) => fake = _FakePairing(ref));
      await tester.tap(find.byKey(const ValueKey('scan-qr')));
      await tester.pumpAndSettle();
      // Le faux service n'enregistre pas le PC : on le fait comme le vrai.
      await tester.tap(find.byKey(const ValueKey('fake-camera')));
      await container.read(pairedPcProvider.notifier).save(_pc);
      await tester.pumpAndSettle();
      expect(fake.calls.single, startsWith('qr:pegasus://pair'));
      expect(find.byKey(const ValueKey('tab-home')), findsOneWidget);
    });

    testWidgets('scan refusé → message d’erreur sur l’écran de scan', (tester) async {
      await _pump(tester,
          size: const Size(360, 640),
          home: const ScanScreen(),
          pairing: (ref) => _FakePairing(ref)..fail = const PairingFailure('Code expiré, générez-en un nouveau'));
      await tester.tap(find.byKey(const ValueKey('fake-camera')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Code expiré, générez-en un nouveau'), findsOneWidget);
      expectCleanLayout(tester);
    });

    testWidgets('code manuel → vérification de l’empreinte → appairage', (tester) async {
      late _FakePairing fake;
      await _pump(tester,
          size: const Size(320, 568),
          home: const ManualPairScreen(),
          pairing: (ref) => fake = _FakePairing(ref));
      await tester.enterText(find.byKey(const ValueKey('host')), '192.168.1.20');
      await tester.enterText(find.byKey(const ValueKey('code')), '482193');
      await tester.pump();
      await tester.pump();
      expect(find.text('ABCDEFGH'), findsOneWidget);
      expectCleanLayout(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-fingerprint')));
      await tester.pump();
      expect(fake.calls, [
        'probe:192.168.1.20:47800',
        'code:192.168.1.20:47800:ABCDEFGH-rest-of-fingerprint:482193',
      ]);
    });

    testWidgets('empreinte différente → retour au formulaire, aucun appairage', (tester) async {
      late _FakePairing fake;
      await _pump(tester,
          size: const Size(393, 852),
          home: const ManualPairScreen(),
          pairing: (ref) => fake = _FakePairing(ref));
      await tester.enterText(find.byKey(const ValueKey('host')), '192.168.1.20');
      await tester.enterText(find.byKey(const ValueKey('code')), '482193');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reject-fingerprint')));
      await tester.pump();
      expect(find.byKey(const ValueKey('continue')), findsOneWidget);
      expect(fake.calls, ['probe:192.168.1.20:47800']);
    });

    testWidgets('code en 6 cases xxx-xxx, chiffres uniquement', (tester) async {
      await _pump(tester, size: const Size(320, 568), home: const ManualPairScreen());
      expect(find.byKey(const ValueKey('pin-cell-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-cell-5')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('code')), '4a8-21');
      await tester.pump();
      final cells = [for (var i = 0; i < 6; i++) find.descendant(of: find.byKey(ValueKey('pin-cell-$i')), matching: find.byType(Text))];
      expect(tester.widget<Text>(cells[0]).data, '4');
      expect(tester.widget<Text>(cells[1]).data, '8');
      expect(tester.widget<Text>(cells[2]).data, '2');
      expect(tester.widget<Text>(cells[3]).data, '1');
      expect(tester.widget<Text>(cells[4]).data, '');
      expectCleanLayout(tester);
    });

    testWidgets('adresse : virgules converties en points, ip:port collé réparti', (tester) async {
      late _FakePairing fake;
      await _pump(tester,
          size: const Size(393, 852),
          home: const ManualPairScreen(),
          pairing: (ref) => fake = _FakePairing(ref));
      await tester.enterText(find.byKey(const ValueKey('host')), '192,168,1,76');
      await tester.pump();
      expect(find.text('192.168.1.76'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('host')), '192.168.1.76:47801');
      await tester.enterText(find.byKey(const ValueKey('code')), '123456');
      await tester.pump();
      await tester.pump();
      expect(fake.calls.first, 'probe:192.168.1.76:47801');
    });

    testWidgets('oublier le PC → retour à l’association', (tester) async {
      await _pump(tester, size: const Size(393, 852), pc: _pc, link: _linkStates['connecté']);
      await tester.tap(find.byKey(const ValueKey('tab-pc')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('forget')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-forget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan-qr')), findsOneWidget);
    });

    testWidgets('accès refusé → bouton Réassocier', (tester) async {
      await _pump(tester, size: const Size(393, 852), pc: _pc, link: _linkStates['non autorisé']);
      expect(find.byKey(const ValueKey('repair')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repair')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan-qr')), findsOneWidget);
    });

    testWidgets('en attente → Réessayer relance la connexion', (tester) async {
      final container = await _pump(tester, size: const Size(393, 852), pc: _pc, link: _linkStates['nouvel essai']);
      await tester.tap(find.byKey(const ValueKey('retry')));
      expect((container.read(linkStateProvider.notifier) as _FixedLink).reconnects, 1);
    });

    testWidgets('PC révoqué → message sur l’écran d’association', (tester) async {
      final container = await _pump(tester, size: const Size(360, 640));
      container.read(pairingNoticeProvider.notifier).show('« PC » a révoqué l’accès de ce téléphone.');
      await tester.pump();
      expect(find.byKey(const ValueKey('pairing-notice')), findsOneWidget);
      expectCleanLayout(tester);
    });
  });
}
