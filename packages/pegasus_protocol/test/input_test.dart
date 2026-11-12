import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:test/test.dart';

Matcher get _invalid => throwsA(isA<InputValidationError>());

void main() {
  test('parseDelta : nombres, valeurs par défaut, bornes', () {
    expect(parseDelta({'dx': 3.5, 'dy': -1}), (dx: 3.5, dy: -1.0));
    expect(parseDelta({'dx': 2}), (dx: 2.0, dy: 0.0));
    expect(parseDelta({'dx': 1e9, 'dy': -1e9}), (dx: InputLimits.maxMove, dy: -InputLimits.maxMove));
    expect(parseDelta({'dy': 999}, scroll: true).dy, InputLimits.maxScroll);
    expect(() => parseDelta({'dx': 'a'}), _invalid);
    expect(() => parseDelta({'dx': double.nan}), _invalid);
  });

  test('parseButton', () {
    expect(parseButton({'button': 'left', 'state': 'down'}), (button: MouseButton.left, down: true));
    expect(parseButton({'button': 'right', 'state': 'up'}), (button: MouseButton.right, down: false));
    expect(() => parseButton({'button': 'x', 'state': 'up'}), _invalid);
    expect(() => parseButton({'button': 'left', 'state': 'hold'}), _invalid);
  });

  test('parseClick', () {
    expect(parseClick({}), (button: MouseButton.left, count: 1));
    expect(parseClick({'button': 'middle', 'count': 2}), (button: MouseButton.middle, count: 2));
    expect(() => parseClick({'count': 3}), _invalid);
  });

  test('parseText : Unicode complet, 1000 caractères max', () {
    expect(parseText({'text': 'Héllo 👋'}), 'Héllo 👋');
    expect(parseText({'text': '😀' * 1000}), hasLength(2000));
    expect(() => parseText({'text': 'a' * 1001}), _invalid);
    expect(() => parseText({'text': ''}), _invalid);
    expect(() => parseText({}), _invalid);
  });

  test('parseKey : touches et modificateurs de la spec', () {
    final altTab = parseKey({'key': 'tab', 'modifiers': ['alt']});
    expect(altTab.key, 'tab');
    expect(altTab.modifiers, [KeyModifier.alt]);
    expect(parseKey({'key': 'win'}).modifiers, isEmpty);
    expect(parseKey({'key': 'c', 'modifiers': ['ctrl', 'ctrl']}).modifiers, [KeyModifier.ctrl]);
    for (final k in ['escape', 'f12', 'a', 'z', '0', '9', 'pagedown', 'printscreen']) {
      expect(parseKey({'key': k}).key, k);
    }
    expect(parseKey({'key': 'a'}).repeat, 1);
    expect(parseKey({'key': 'backspace', 'repeat': 8}).repeat, 8);
    expect(() => parseKey({'key': 'a', 'repeat': 0}), _invalid);
    expect(() => parseKey({'key': 'a', 'repeat': 101}), _invalid);
    expect(() => parseKey({'key': 'A'}), _invalid);
    expect(() => parseKey({'key': 'f13'}), _invalid);
    expect(() => parseKey({'key': 'a', 'modifiers': ['hyper']}), _invalid);
    expect(() => parseKey({'key': 'a', 'modifiers': 'ctrl'}), _invalid);
  });
}
