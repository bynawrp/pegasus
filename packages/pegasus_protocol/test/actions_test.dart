import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:test/test.dart';

Matcher get _invalid => throwsA(isA<InputValidationError>());

void main() {
  test('parseAudioSet', () {
    expect(parseAudioSet({'volume': 40}), (volume: 40, muted: null));
    expect(parseAudioSet({'volume': 33.6, 'muted': true}), (volume: 34, muted: true));
    expect(parseAudioSet({'muted': false}), (volume: null, muted: false));
    expect(() => parseAudioSet({}), _invalid);
    expect(() => parseAudioSet({'volume': 101}), _invalid);
    expect(() => parseAudioSet({'volume': -1}), _invalid);
    expect(() => parseAudioSet({'muted': 'oui'}), _invalid);
  });

  test('AudioState JSON borné', () {
    expect(AudioState.fromJson({'volume': 150, 'muted': true}), const AudioState(volume: 100, muted: true));
    expect(AudioState.fromJson(const AudioState(volume: 7, muted: false).toJson()), const AudioState(volume: 7, muted: false));
  });

  test('alimentation : confirmation exigée pour les actions destructrices', () {
    expect(PowerAction.fromOp('power.shutdown'), PowerAction.shutdown);
    expect(PowerAction.fromOp('power.boom'), isNull);
    checkPowerConfirmation(PowerAction.lock, {});
    checkPowerConfirmation(PowerAction.sleep, {});
    for (final a in [PowerAction.logoff, PowerAction.restart, PowerAction.shutdown]) {
      expect(() => checkPowerConfirmation(a, {}), _invalid, reason: a.name);
      expect(() => checkPowerConfirmation(a, {'confirmed': 'true'}), _invalid, reason: a.name);
      checkPowerConfirmation(a, {'confirmed': true});
    }
  });

  test('parseUrl : http(s) seulement, 2048 max', () {
    expect(parseUrl({'url': ' https://exemple.fr/a?b=1 '}).toString(), 'https://exemple.fr/a?b=1');
    expect(parseUrl({'url': 'http://192.168.1.2:8080'}).host, '192.168.1.2');
    for (final bad in ['file:///C:/Windows/System32/cmd.exe', 'javascript:alert(1)', 'ftp://x.fr', 'exemple.fr', 'https://', '']) {
      expect(() => parseUrl({'url': bad}), _invalid, reason: bad);
    }
    expect(() => parseUrl({'url': 'https://x.fr/${'a' * 2048}'}), _invalid);
    expect(() => parseUrl({}), _invalid);
  });

  test('extractUrl : lien dans un texte partagé', () {
    expect(extractUrl('Regarde ça : https://youtu.be/abc?t=3.'), 'https://youtu.be/abc?t=3');
    expect(extractUrl('(voir http://exemple.fr/page)'), 'http://exemple.fr/page');
    expect(extractUrl('pas de lien ici'), isNull);
  });

  test('parseAppId et FavoriteApp', () {
    expect(parseAppId({'id': 'abc'}), 'abc');
    expect(() => parseAppId({'id': ''}), _invalid);
    expect(() => parseAppId({'id': 'x' * 200}), _invalid);
    expect(FavoriteApp.fromJson({'id': 'a', 'name': 'Steam', 'icon': ''})!.icon, isNull);
    expect(FavoriteApp.fromJson({'name': 'x'}), isNull);
  });
}
