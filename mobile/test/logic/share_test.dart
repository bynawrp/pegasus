import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/core/share_intake.dart';

void main() {
  test('lien pegasus://open?url=… (raccourci iOS)', () {
    expect(incomingUrl(link: Uri.parse('pegasus://open?url=https%3A%2F%2Fyoutu.be%2Fabc')), 'https://youtu.be/abc');
    expect(incomingUrl(link: Uri.parse('pegasus://open?url=Regarde%20https%3A%2F%2Fx.fr')), 'https://x.fr');
    expect(incomingUrl(link: Uri.parse('pegasus://pair?v=1')), isNull);
    expect(incomingUrl(link: Uri.parse('https://exemple.fr')), isNull);
    expect(incomingUrl(link: Uri.parse('pegasus://open')), isNull);
  });

  test('texte partagé (Android) : premier lien http(s)', () {
    expect(incomingUrl(sharedText: 'Regarde ça https://youtu.be/abc !'), 'https://youtu.be/abc');
    expect(incomingUrl(sharedText: 'pas de lien'), isNull);
    expect(incomingUrl(), isNull);
  });
}
