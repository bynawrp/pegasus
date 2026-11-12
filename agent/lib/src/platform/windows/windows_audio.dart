import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

/// Volume général du PC via Core Audio (`IAudioEndpointVolume`, COM).
///
/// Chaque appel reprend le périphérique de sortie par défaut : changer de
/// casque ou d'enceintes est donc pris en compte sans redémarrer l'agent.
class WindowsAudio {
  WindowsAudio() {
    // Déjà initialisé dans un autre mode (RPC_E_CHANGED_MODE) : sans gravité.
    _coInitializeEx(nullptr, _coinitMultithreaded);
  }

  AudioState get() => _withVolume((v) {
        return using((arena) {
          final level = arena<Float>();
          final mute = arena<Int32>();
          _check(_fn(v, 9).cast<NativeFunction<_GetFloatN>>().asFunction<_GetFloatD>()(v, level), 'GetMasterVolumeLevelScalar');
          _check(_fn(v, 15).cast<NativeFunction<_GetIntN>>().asFunction<_GetIntD>()(v, mute), 'GetMute');
          return AudioState(volume: (level.value * 100).round().clamp(0, 100), muted: mute.value != 0);
        });
      });

  AudioState set({int? volume, bool? muted}) {
    _withVolume((v) {
      if (volume != null) {
        _check(_fn(v, 7).cast<NativeFunction<_SetFloatN>>().asFunction<_SetFloatD>()(v, volume.clamp(0, 100) / 100, nullptr), 'SetMasterVolumeLevelScalar');
      }
      if (muted != null) {
        _check(_fn(v, 14).cast<NativeFunction<_SetIntN>>().asFunction<_SetIntD>()(v, muted ? 1 : 0, nullptr), 'SetMute');
      }
    });
    return get();
  }

  T _withVolume<T>(T Function(Pointer<Pointer<IntPtr>> volume) action) {
    return using((arena) {
      final enumerator = arena<Pointer<Pointer<IntPtr>>>();
      _check(
        _coCreateInstance(_guid(arena, _clsidEnumerator), nullptr, _clsctxAll, _guid(arena, _iidEnumerator), enumerator.cast()),
        'CoCreateInstance(MMDeviceEnumerator)',
      );
      final e = enumerator.value;
      final device = arena<Pointer<Pointer<IntPtr>>>();
      try {
        // GetDefaultAudioEndpoint(eRender, eMultimedia).
        _check(_fn(e, 4).cast<NativeFunction<_DefaultEndpointN>>().asFunction<_DefaultEndpointD>()(e, 0, 1, device.cast()), 'GetDefaultAudioEndpoint');
        final d = device.value;
        final volume = arena<Pointer<Pointer<IntPtr>>>();
        try {
          _check(_fn(d, 3).cast<NativeFunction<_ActivateN>>().asFunction<_ActivateD>()(d, _guid(arena, _iidEndpointVolume), _clsctxAll, nullptr, volume.cast()), 'Activate');
          final v = volume.value;
          try {
            return action(v);
          } finally {
            _release(v);
          }
        } finally {
          _release(d);
        }
      } finally {
        _release(e);
      }
    });
  }

  static void _release(Pointer<Pointer<IntPtr>> obj) => _fn(obj, 2).cast<NativeFunction<_ReleaseN>>().asFunction<_ReleaseD>()(obj);

  static void _check(int hr, String what) {
    if (hr < 0) throw StateError('$what a échoué (0x${(hr & 0xFFFFFFFF).toRadixString(16)})');
  }

  /// Adresse de la fonction n° [index] de la table virtuelle de l'objet COM [obj].
  static Pointer<Void> _fn(Pointer<Pointer<IntPtr>> obj, int index) => Pointer.fromAddress(obj.value[index]);

  static Pointer<_Guid> _guid(Arena arena, String text) {
    final hex = text.replaceAll('-', '');
    final g = arena<_Guid>();
    g.ref
      ..data1 = int.parse(hex.substring(0, 8), radix: 16)
      ..data2 = int.parse(hex.substring(8, 12), radix: 16)
      ..data3 = int.parse(hex.substring(12, 16), radix: 16);
    for (var i = 0; i < 8; i++) {
      g.ref.data4[i] = int.parse(hex.substring(16 + i * 2, 18 + i * 2), radix: 16);
    }
    return g;
  }

  static const _clsidEnumerator = 'BCDE0395-E52F-467C-8E3D-C4579291692E';
  static const _iidEnumerator = 'A95664D2-9614-4F35-A746-DE8DB63617E6';
  static const _iidEndpointVolume = '5CDF2C82-841E-4546-9722-0CF74078229A';
  static const _clsctxAll = 0x17;
  static const _coinitMultithreaded = 0x0;
}

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

typedef _ReleaseN = Uint32 Function(Pointer);
typedef _ReleaseD = int Function(Pointer);
typedef _DefaultEndpointN = Int32 Function(Pointer, Int32, Int32, Pointer);
typedef _DefaultEndpointD = int Function(Pointer, int, int, Pointer);
typedef _ActivateN = Int32 Function(Pointer, Pointer<_Guid>, Uint32, Pointer, Pointer);
typedef _ActivateD = int Function(Pointer, Pointer<_Guid>, int, Pointer, Pointer);
typedef _GetFloatN = Int32 Function(Pointer, Pointer<Float>);
typedef _GetFloatD = int Function(Pointer, Pointer<Float>);
typedef _SetFloatN = Int32 Function(Pointer, Float, Pointer);
typedef _SetFloatD = int Function(Pointer, double, Pointer);
typedef _GetIntN = Int32 Function(Pointer, Pointer<Int32>);
typedef _GetIntD = int Function(Pointer, Pointer<Int32>);
typedef _SetIntN = Int32 Function(Pointer, Int32, Pointer);
typedef _SetIntD = int Function(Pointer, int, Pointer);

final _ole32 = DynamicLibrary.open('ole32.dll');
final _coInitializeEx =
    _ole32.lookupFunction<Int32 Function(Pointer, Uint32), int Function(Pointer, int)>('CoInitializeEx');
final _coCreateInstance = _ole32.lookupFunction<
    Int32 Function(Pointer<_Guid>, Pointer, Uint32, Pointer<_Guid>, Pointer),
    int Function(Pointer<_Guid>, Pointer, int, Pointer<_Guid>, Pointer)>('CoCreateInstance');
