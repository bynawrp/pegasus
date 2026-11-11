import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

void main() {
  test('le thème sombre utilise la palette Pegasus', () {
    final theme = PegasusTheme.dark();
    expect(theme.colorScheme.primary, PegasusColors.accent);
    expect(theme.scaffoldBackgroundColor, PegasusColors.background);
  });
}
