// Paquet 3 : médias, son, alimentation, applications et liens côté agent.
// Aucune action réelle d'alimentation n'est jamais exécutée ici : le
// contrôleur système est un enregistreur.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus_agent/src/core/agent_controller.dart';
import 'package:pegasus_agent/src/core/agent_store.dart';
import 'package:pegasus_agent/src/modules/apps/app_catalog.dart';
import 'package:pegasus_agent/src/modules/system/system_modules.dart';
import 'package:pegasus_agent/src/platform/input_controller.dart';
import 'package:pegasus_agent/src/platform/system_controller.dart';
import 'package:pegasus_agent/src/platform/windows/windows_audio.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

final _isRealWindows = Platform.isWindows && Platform.environment['CI'] != 'true';

Matcher _fails(ErrorCode code) => throwsA(isA<RequestFailedException>().having((e) => e.code, 'code', code));

Future<Directory> _tempDir() async {
  final dir = await Directory.systemTemp.createTemp('pegasus_sys_test');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
  return dir;
}

const _steam = Favorite(id: 'steam', name: 'Steam', path: r'C:\Start\Steam.lnk', icon: 'aWNvbg==');

void main() {
  group('Modules media / power / apps via le serveur', () {
    late AgentServer server;
    late RecordingSystemController system;
    late PegasusConnection conn;
    var favorites = <Favorite>[_steam];

    setUp(() async {
      final identity = AgentIdentity.generate(name: 'PC');
      server = AgentServer(identity: identity, config: AgentServerConfig(port: 0, address: InternetAddress.loopbackIPv4));
      system = RecordingSystemController();
      favorites = [_steam];
      registerMediaModule(server, system);
      registerPowerModule(server, system, delay: const Duration(milliseconds: 50));
      registerAppsModule(server, system, () => favorites);
      await server.start();
      addTearDown(server.dispose);
      final secret = server.pairing.renew();
      conn = await PegasusClient.connect(host: '127.0.0.1', port: server.port, fingerprint: identity.fingerprint);
      addTearDown(conn.close);
      final r = await conn.pair(token: secret.token, device: const DeviceDescriptor(id: 'd', name: 'T', platform: 'ios'));
      await conn.authenticate(agentId: r.agentId, deviceId: 'd', deviceSecret: r.deviceSecret);
    });

    test('touches multimédia', () async {
      await conn.request('media.play_pause');
      await conn.request('media.next');
      await conn.request('media.previous');
      expect(system.calls, ['media playPause', 'media next', 'media previous']);
    });

    test('volume : lecture, réglage, évènement audio.changed pour tous', () async {
      expect(await conn.request('audio.get'), {'volume': 50, 'muted': false});
      final evt = conn.events.firstWhere((e) => e.op == 'audio.changed');
      expect(await conn.request('audio.set', {'volume': 30}), {'volume': 30, 'muted': false});
      expect((await evt).data, {'volume': 30, 'muted': false});
      expect(await conn.request('audio.set', {'muted': true}), {'volume': 30, 'muted': true});
      await expectLater(conn.request('audio.set', {'volume': 300}), _fails(ErrorCode.badRequest));
      await expectLater(conn.request('audio.set', const {}), _fails(ErrorCode.badRequest));
    });

    test('alimentation : réponse d’abord, action ensuite', () async {
      await conn.request('power.lock');
      expect(system.calls, isEmpty, reason: 'l’action part après la réponse');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(system.calls, ['power lock']);
    });

    test('alimentation destructrice sans confirmation → refusée, jamais exécutée', () async {
      for (final op in ['power.shutdown', 'power.restart', 'power.logoff']) {
        await expectLater(conn.request(op), _fails(ErrorCode.badRequest), reason: op);
        await expectLater(conn.request(op, {'confirmed': 'yes'}), _fails(ErrorCode.badRequest), reason: op);
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(system.calls, isEmpty);
      await conn.request('power.shutdown', {'confirmed': true});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(system.calls, ['power shutdown']);
    });

    test('alimentation : module désactivé ou pause → refusé', () async {
      server.setModule('power', false);
      await expectLater(conn.request('power.lock'), _fails(ErrorCode.forbidden));
      server.setModule('power', true);
      server.setPaused(true);
      await expectLater(conn.request('power.sleep'), _fails(ErrorCode.paused));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(system.calls, isEmpty);
    });

    test('apps.list : favoris sans chemin (jamais exposé au téléphone)', () async {
      final res = await conn.request('apps.list');
      expect(res, {
        'apps': [
          {'id': 'steam', 'name': 'Steam', 'icon': 'aWNvbg=='},
        ],
      });
      expect(jsonEncode(res), isNot(contains('Start')));
    });

    test('apps.launch : uniquement un favori connu', () async {
      await conn.request('apps.launch', {'id': 'steam'});
      expect(system.calls, [r'launch C:\Start\Steam.lnk']);
      await expectLater(conn.request('apps.launch', {'id': r'C:\Windows\System32\cmd.exe'}), _fails(ErrorCode.badRequest));
      await expectLater(conn.request('apps.launch', const {}), _fails(ErrorCode.badRequest));
      system.launchResult = false;
      await expectLater(conn.request('apps.launch', {'id': 'steam'}), _fails(ErrorCode.rejected));
    });

    test('url.open : http(s) uniquement', () async {
      await conn.request('url.open', {'url': 'https://exemple.fr/video'});
      for (final bad in ['file:///C:/Windows/System32/cmd.exe', 'javascript:alert(1)', 'notepad']) {
        await expectLater(conn.request('url.open', {'url': bad}), _fails(ErrorCode.badRequest), reason: bad);
      }
      expect(system.calls, ['url https://exemple.fr/video']);
    });

    test('AudioWatcher : changement de volume sur le PC → audio.changed', () async {
      final watcher = AudioWatcher(server, system, interval: const Duration(hours: 1));
      watcher.poll(); // Mémorise l'état initial.
      system.state = const AudioState(volume: 77, muted: false);
      final evt = conn.events.firstWhere((e) => e.op == 'audio.changed');
      watcher.poll();
      expect((await evt).data, {'volume': 77, 'muted': false});
    });
  });

  group('Menu Démarrer', () {
    test('raccourcis trouvés, entrées techniques écartées, doublons fusionnés', () async {
      final dir = await _tempDir();
      Future<void> touch(String rel) async {
        final f = File('${dir.path}/$rel');
        await f.parent.create(recursive: true);
        await f.writeAsString('x');
      }

      await touch('Steam/Steam.lnk');
      await touch('Steam/Uninstall Steam.lnk');
      await touch('Discord Inc/Discord.lnk');
      await touch('Outils/Lisez-moi.lnk');
      await touch('Notes.txt');
      await touch('Autre dossier/steam.lnk');
      final apps = await StartMenuScanner([dir, Directory('${dir.path}/inexistant')]).scan();
      expect(apps.map((a) => a.name), ['Discord', 'Steam']);
      expect(apps.first.id, InstalledApp.idFor(apps.first.path));
      expect(apps.first.id, hasLength(16));
    });
  });

  group('Favoris (contrôleur + stockage)', () {
    test('ajout avec icône, ordre, retrait, conservés après redémarrage', () async {
      final dir = await _tempDir();
      ProviderContainer make() {
        final c = ProviderContainer(overrides: [
          agentDirectoryProvider.overrideWith((ref) async => dir),
          agentServerConfigProvider.overrideWithValue(AgentServerConfig(port: 0, address: InternetAddress.loopbackIPv4)),
          inputControllerProvider.overrideWithValue(RecordingInputController()),
          systemControllerProvider.overrideWithValue(RecordingSystemController()),
          iconExtractorProvider.overrideWithValue(_FakeIcons()),
        ]);
        addTearDown(c.dispose);
        c.read(agentControllerProvider);
        return c;
      }

      final c = make();
      while (c.read(agentControllerProvider).status != AgentStatus.running) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final ctrl = c.read(agentControllerProvider.notifier);
      const a = InstalledApp(id: 'a', name: 'Steam', path: r'C:\a.lnk');
      const b = InstalledApp(id: 'b', name: 'Discord', path: r'C:\b.lnk');
      await ctrl.addFavorite(a);
      await ctrl.addFavorite(b);
      await ctrl.addFavorite(a); // doublon ignoré
      ctrl.moveFavorite('b', -1);
      expect(c.read(agentControllerProvider).favorites.map((f) => f.name), ['Discord', 'Steam']);
      expect(c.read(agentControllerProvider).favorites.first.icon, 'icon:C:\\b.lnk');
      ctrl.removeFavorite('a');
      await ctrl.flush();
      c.dispose();

      final data = await AgentStore(dir).loadOrCreate(defaultName: 'PC');
      expect(data.favorites.map((f) => f.id), ['b']);
    });
  });

  group('Windows réel (poste de dev uniquement)', () {
    test('Core Audio : lecture puis réécriture de la même valeur', () {
      final audio = WindowsAudio();
      final before = audio.get();
      expect(before.volume, inInclusiveRange(0, 100));
      expect(audio.set(volume: before.volume, muted: before.muted), before);
    }, skip: _isRealWindows ? false : 'Windows avec session interactive uniquement');

    test('icône extraite en PNG', () async {
      final icon = await const IconExtractor().extract(r'C:\Windows\System32\notepad.exe');
      expect(icon, isNotNull);
      final bytes = base64.decode(icon!);
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
    }, skip: _isRealWindows ? false : 'Windows avec session interactive uniquement');
  });
}

class _FakeIcons implements IconExtractor {
  @override
  Future<String?> extract(String path) async => 'icon:$path';
}
