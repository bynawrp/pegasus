// Tests d'interface de l'agent : aucune vue ne déborde, à toutes les tailles
// de fenêtre autorisées et dans tous les états (principe « zéro overflow »).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_agent/main.dart';
import 'package:pegasus_agent/src/core/agent_controller.dart';
import 'package:pegasus_agent/src/modules/apps/app_catalog.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_ui/testing.dart';

class _FakeScanner extends StartMenuScanner {
  _FakeScanner() : super(const []);

  @override
  Future<List<InstalledApp>> scan() async => [
        for (var i = 0; i < 60; i++)
          InstalledApp(id: 'app$i', name: i == 0 ? 'Une application au nom vraiment très très long pour tester' : 'Application $i', path: 'C:/a$i.lnk'),
      ];
}

class FakeAgentController extends AgentController {
  FakeAgentController(this.initial);
  final AgentViewState initial;
  final calls = <String>[];

  @override
  AgentViewState build() => initial;

  @override
  void renewPairing() => calls.add('renew');

  @override
  void setPaused(bool paused) {
    calls.add('pause:$paused');
    state = state.copyWith(paused: paused);
  }

  @override
  Future<void> revoke(String deviceId) async => calls.add('revoke:$deviceId');

  @override
  void rename(String deviceId, String name) => calls.add('rename:$deviceId:$name');

  @override
  Future<void> addFavorite(InstalledApp app) async => calls.add('add:${app.id}');

  @override
  void removeFavorite(String id) => calls.add('remove:$id');
}

PairedDevice _device(int i) => PairedDevice(
      id: 'd$i',
      name: i == 0 ? 'Téléphone avec un nom vraiment très très long pour tester' : 'Téléphone $i',
      platform: i.isEven ? 'android' : 'ios',
      secret: 's',
      pairedAt: DateTime(2026, 11, 1, 10),
      lastSeen: i == 3 ? DateTime(2026, 11, 10, 18, 5) : null,
    );

Favorite _fav(int i) => Favorite(id: 'app$i', name: i == 0 ? 'Favori au nom très très long pour la mise en page' : 'Favori $i', path: 'C:/a$i.lnk');

AgentViewState _running({int devices = 3, int connected = 2, int activity = 30, bool paused = false, int favorites = 3}) =>
    AgentViewState(
      status: AgentStatus.running,
      agentName: 'PC-BUREAU-GAMING-DE-COMPETITION',
      agentId: '0b1c2d3e-uuid',
      fingerprint: 'Zx9_aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5',
      addresses: const ['192.168.1.20'],
      paused: paused,
      pairing: PairingSecret(
        token: 'tok_en-xyz',
        code: '482193',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
      devices: [for (var i = 0; i < devices; i++) _device(i)],
      favorites: [for (var i = 0; i < favorites; i++) _fav(i)],
      connected: {for (var i = 0; i < connected; i++) 'd$i'},
      activity: [
        for (var i = 0; i < activity; i++)
          ActivityEntry(DateTime(2026, 11, 11, 14, i % 60),
              i.isEven ? 'Téléphone $i · power.lock' : 'Téléphone $i connecté avec un libellé long',
              ok: i % 5 != 0),
      ],
    );

final _states = <String, AgentViewState>{
  'démarrage': const AgentViewState(),
  'actif': _running(),
  'en pause': _running(paused: true),
  'vide': _running(devices: 0, connected: 0, activity: 0),
  'beaucoup d’appareils': _running(devices: 40, connected: 12, favorites: 30),
  'code verrouillé': AgentViewState(
    status: AgentStatus.running,
    agentName: 'PC',
    fingerprint: 'abcdefghijk',
    addresses: const ['10.0.0.2'],
    pairingLocked: true,
  ),
  'code expiré': AgentViewState(
    status: AgentStatus.running,
    agentName: 'PC',
    fingerprint: 'abcdefghijk',
    addresses: const ['10.0.0.2'],
    pairing: PairingSecret(token: 't', code: '111111', expiresAt: DateTime(2020)),
  ),
  'sans réseau': const AgentViewState(status: AgentStatus.running, agentName: 'PC', fingerprint: 'abc'),
  'erreur': const AgentViewState(
    status: AgentStatus.error,
    error: 'Impossible d’écouter sur le port 47800 (Une seule utilisation de chaque adresse de socket est habituellement autorisée)',
  ),
};

const _sizes = [Size(960, 600), Size(1100, 700), Size(1920, 1080)];

Future<FakeAgentController> _pump(WidgetTester tester, AgentViewState state, Size size,
    {double textScale = 1}) async {
  setScreenSize(tester, size);
  final fake = FakeAgentController(state);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      agentControllerProvider.overrideWith(() => fake),
      startMenuScannerProvider.overrideWithValue(_FakeScanner()),
    ],
    child: withTextScale(textScale, const PegasusAgentApp()),
  ));
  await tester.pump();
  return fake;
}

void main() {
  setUpAll(loadPegasusFonts);

  for (final MapEntry(key: name, value: state) in _states.entries) {
    for (final size in _sizes) {
      testWidgets('zéro overflow · $name · ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        await _pump(tester, state, size);
        expectCleanLayout(tester);
        await tester.tap(find.byKey(const ValueKey('nav-devices')));
        await tester.pump();
        expectCleanLayout(tester);
        await tester.tap(find.byKey(const ValueKey('nav-favorites')));
        await tester.pump();
        await tester.pump();
        expectCleanLayout(tester);
      });
    }
  }

  testWidgets('zéro overflow · texte agrandi ×1.3 · fenêtre minimale', (tester) async {
    await _pump(tester, _running(devices: 12, connected: 3), const Size(960, 600), textScale: 1.3);
    expectCleanLayout(tester);
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pump();
    expectCleanLayout(tester);
  });

  testWidgets('favoris : recherche, ajout, retrait', (tester) async {
    final fake = await _pump(tester, _running(favorites: 1), const Size(1100, 700));
    await tester.tap(find.byKey(const ValueKey('nav-favorites')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('app-search')), 'Application 4');
    await tester.pump();
    expect(find.byKey(const ValueKey('app-app4')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-app5')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-app-app4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remove-fav-app0')));
    await tester.pump();
    expect(fake.calls, ['add:app4', 'remove:app0']);
    expectCleanLayout(tester);
  });

  testWidgets('accueil : QR et code manuel affichés', (tester) async {
    await _pump(tester, _running(), const Size(1100, 700));
    expect(find.byKey(const ValueKey('pairing-qr')), findsOneWidget);
    expect(find.text('482 193'), findsOneWidget);
    expect(find.text('ACTIF'), findsOneWidget);
  });

  testWidgets('code verrouillé → bouton nouveau code', (tester) async {
    final fake = await _pump(tester, _states['code verrouillé']!, const Size(1100, 700));
    expect(find.byKey(const ValueKey('pairing-qr')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('renew-pairing')));
    expect(fake.calls, ['renew']);
  });

  testWidgets('pause puis reprise', (tester) async {
    final fake = await _pump(tester, _running(), const Size(1100, 700));
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    expect(find.text('EN PAUSE'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resume')));
    await tester.pump();
    expect(fake.calls, ['pause:true', 'pause:false']);
  });

  testWidgets('appareils : pagination sans défilement', (tester) async {
    await _pump(tester, _running(devices: 40, connected: 2), const Size(960, 600));
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pump();
    expect(find.byType(Scrollable), findsNothing);
    expect(find.textContaining(' / '), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    expect(find.textContaining('2 / '), findsOneWidget);
    expectCleanLayout(tester);
  });

  testWidgets('révoquer demande confirmation', (tester) async {
    final fake = await _pump(tester, _running(), const Size(1100, 700));
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('revoke-d1')));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('confirm-revoke')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['revoke:d1']);
  });

  testWidgets('renommer un appareil', (tester) async {
    final fake = await _pump(tester, _running(), const Size(1100, 700));
    await tester.tap(find.byKey(const ValueKey('nav-devices')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rename-d1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pixel');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['rename:d1:Pixel']);
  });
}
