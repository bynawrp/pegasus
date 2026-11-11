import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/pairing/manual_pair_screen.dart';

void main() {
  test('parseHostInput : IPv4, virgules, port collé', () {
    expect(parseHostInput('192.168.1.20'), (host: '192.168.1.20', port: null));
    expect(parseHostInput(' 192,168,1,20 '), (host: '192.168.1.20', port: null));
    expect(parseHostInput('192.168.1.20:47801'), (host: '192.168.1.20', port: 47801));
    for (final bad in ['', '192.168.1', '192.168.1.256', 'abc', '1.2.3.4:0', '1.2.3.4:70000']) {
      expect(parseHostInput(bad), isNull, reason: bad);
    }
  });

  test('HostInputFormatter : garde chiffres, points et deux-points', () {
    const f = HostInputFormatter();
    TextEditingValue v(String t) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    expect(f.formatEditUpdate(TextEditingValue.empty, v('192,168')).text, '192.168');
    expect(f.formatEditUpdate(TextEditingValue.empty, v('19a2. 1-6')).text, '192.16');
    expect(f.formatEditUpdate(TextEditingValue.empty, v('10.0.0.2:47800')).text, '10.0.0.2:47800');
  });
}
