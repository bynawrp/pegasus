/// Outils de test partagés : polices réelles et vérification « zéro overflow ».
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Charge les vraies polices Pegasus pour que les tests de mise en page
/// mesurent le texte comme sur l'appareil.
///
/// [packageRoot] : chemin vers `packages/pegasus_ui` depuis le dossier du test.
Future<void> loadPegasusFonts({String packageRoot = '../packages/pegasus_ui'}) async {
  Future<ByteData> read(String name) async {
    final bytes = await File('$packageRoot/fonts/$name').readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  final families = {
    'packages/pegasus_ui/Barlow': ['Barlow-Regular.ttf', 'Barlow-Medium.ttf', 'Barlow-SemiBold.ttf'],
    'packages/pegasus_ui/BarlowCondensed': ['BarlowCondensed-SemiBold.ttf', 'BarlowCondensed-Bold.ttf'],
    'packages/pegasus_ui/JetBrainsMono': ['JetBrainsMono-Variable.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(read(file));
    }
    await loader.load();
  }
}

/// Fixe la taille logique de l'écran simulé.
void setScreenSize(WidgetTester tester, Size size, {double pixelRatio = 1}) {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = size * pixelRatio;
  addTearDown(tester.view.reset);
}

/// Échoue si un widget a débordé (RenderFlex overflow, etc.) pendant le rendu.
void expectNoOverflow(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'Débordement ou erreur de rendu : $error');
}

/// Applique un facteur de taille de texte (accessibilité) à [child].
Widget withTextScale(double scale, Widget child) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    );
