import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  test('thème par défaut : palette Néon, sombre, accent magenta', () {
    final theme = PegasusTheme.build();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFFFF2E88));
    expect(theme.extension<PegasusColors>(), isNotNull);
  });

  for (final palette in PegasusPalette.values) {
    for (final brightness in Brightness.values) {
      test('${palette.name} ${brightness.name} : contrastes lisibles (≥ 4.5:1)', () {
        final c = PegasusColors.of(palette, brightness);
        expect(_contrast(c.text, c.background), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textMuted, c.background), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textMuted, c.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.accent, c.background), greaterThanOrEqualTo(3.0));
      });
    }
  }
}
