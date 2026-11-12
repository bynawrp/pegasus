import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import '../system_controller.dart';
import 'windows_audio.dart';
import 'windows_input.dart';

/// Windows : Core Audio, touches multimédia (SendInput), alimentation,
/// ShellExecute pour les applications et les liens.
class WindowsSystem implements SystemController {
  WindowsSystem({WindowsAudio? audio, WindowsInputController? input})
      : _audio = audio ?? WindowsAudio(),
        _input = input ?? WindowsInputController();

  final WindowsAudio _audio;
  final WindowsInputController _input;

  static const mediaKeys = {
    MediaCommand.playPause: 0xB3,
    MediaCommand.next: 0xB0,
    MediaCommand.previous: 0xB1,
  };

  @override
  AudioState audio() => _audio.get();

  @override
  AudioState setAudio({int? volume, bool? muted}) => _audio.set(volume: volume, muted: muted);

  @override
  void media(MediaCommand command) {
    final vk = mediaKeys[command]!;
    _input.dispatch([
      RawKey(vk: vk, flags: WinInput.extended),
      RawKey(vk: vk, flags: WinInput.extended | WinInput.keyUp),
    ]);
  }

  @override
  void power(PowerAction action) {
    switch (action) {
      case PowerAction.lock:
        _lockWorkStation();
      case PowerAction.sleep:
        // Veille (et non hibernation), réveil autorisé.
        _setSuspendState(0, 0, 0);
      case PowerAction.logoff:
        Process.run('shutdown', ['/l']);
      case PowerAction.restart:
        Process.run('shutdown', ['/r', '/t', '0']);
      case PowerAction.shutdown:
        Process.run('shutdown', ['/s', '/t', '0']);
    }
  }

  @override
  bool launch(String path) => _shellOpen(path);

  @override
  bool openUrl(Uri url) => _shellOpen(url.toString());

  /// `ShellExecuteW(open)` : le chemin / lien est passé tel quel, jamais
  /// interprété par un interpréteur de commandes.
  static bool _shellOpen(String target) => using((arena) {
        final result = _shellExecute(nullptr, 'open'.toNativeUtf16(allocator: arena),
            target.toNativeUtf16(allocator: arena), nullptr, nullptr, 1 /* SW_SHOWNORMAL */);
        return result.address > 32;
      });
}

final _user32 = DynamicLibrary.open('user32.dll');
final _lockWorkStation = _user32.lookupFunction<Int32 Function(), int Function()>('LockWorkStation');
final _setSuspendState = DynamicLibrary.open('powrprof.dll')
    .lookupFunction<Uint8 Function(Uint8, Uint8, Uint8), int Function(int, int, int)>('SetSuspendState');
final _shellExecute = DynamicLibrary.open('shell32.dll').lookupFunction<
    Pointer Function(Pointer, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Int32),
    Pointer Function(Pointer, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, int)>('ShellExecuteW');
