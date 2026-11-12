import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../colors.dart';
import '../tokens.dart';

/// Logo Pegasus (pégase silhouette) aux couleurs de la palette active.
class PegasusLogo extends StatelessWidget {
  const PegasusLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PegasusColors>();
    final accent = c?.accent ?? const Color(0xFFFF2E88);
    final accent2 = c?.accent2 ?? const Color(0xFF2EF2FF);
    final bg = c?.background ?? const Color(0xFF0B0614);
    String hex(Color x) => '#${(x.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return SvgPicture.string(
      _svg(hex(accent), hex(accent2), hex(bg)),
      width: size,
      height: size,
      semanticsLabel: 'Pegasus',
    );
  }

  static String _svg(String body, String wing, String eye) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
<path fill="$wing" d="M44 62 Q22 58 5 34 Q20 41 31 41 Q18 30 12 13 Q28 26 39 34 Q33 20 33 6 Q48 21 50 46 Z"/>
<path fill="$body" d="M24 92 C25 76 31 63 41 55 Q46 46 50 38 L53 26 L50 12 L58 20 L63 17 L66 26 Q73 30 81 40 Q87 47 84 53 Q81 58 73 56 L64 54 Q60 63 59 72 L59 92 Z"/>
<circle fill="$eye" cx="70" cy="37" r="2.8"/>
</svg>''';

  /// Chemin de l'asset SVG (version Néon).
  static const asset = PegasusAssets.logoSvg;
}
