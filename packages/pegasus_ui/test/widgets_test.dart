import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_ui/pegasus_ui.dart';
import 'package:pegasus_ui/testing.dart';

Widget _app(Widget child) => MaterialApp(theme: PegasusTheme.build(), home: Scaffold(body: child));

void main() {
  setUpAll(() => loadPegasusFonts(packageRoot: '.'));

  testWidgets('le garde-fou détecte bien un débordement', (tester) async {
    setScreenSize(tester, const Size(200, 200));
    await tester.pumpWidget(_app(const Row(children: [SizedBox(width: 300, height: 10)])));
    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('le garde-fou détecte un libellé de bouton sur deux lignes', (tester) async {
    setScreenSize(tester, const Size(300, 300));
    await tester.pumpWidget(_app(Center(
      child: SizedBox(
        width: 120,
        child: FilledButton(onPressed: () {}, child: const Text('Reprendre le contrôle du PC')),
      ),
    )));
    expect(() => expectButtonLabelsOnOneLine(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('PegasusPanel : titre long sans débordement', (tester) async {
    setScreenSize(tester, const Size(200, 120));
    await tester.pumpWidget(_app(const PegasusPanel(
      title: 'Un titre beaucoup trop long pour la carte',
      trailing: Icon(Icons.info),
      child: SizedBox.expand(),
    )));
    expectNoOverflow(tester);
  });

  testWidgets('PegasusLogo s’affiche avec les couleurs de chaque palette', (tester) async {
    for (final palette in PegasusPalette.values) {
      await tester.pumpWidget(MaterialApp(
        theme: PegasusTheme.build(palette: palette),
        home: const PegasusLogo(size: 48),
      ));
      expect(find.byType(PegasusLogo), findsOneWidget);
      expectNoOverflow(tester);
    }
  });
}
