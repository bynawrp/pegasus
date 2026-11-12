import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Chiffrement des secrets stockés sur disque (clé privée, secrets des appareils).
abstract class SecretProtector {
  String protect(String plain);
  String unprotect(String stored);

  /// DPAPI sous Windows (lié à la session utilisateur), sinon aucun chiffrement.
  factory SecretProtector.platform() =>
      Platform.isWindows ? DpapiProtector() : const PlainProtector();
}

/// Aucun chiffrement (tests, plateformes non encore supportées).
class PlainProtector implements SecretProtector {
  const PlainProtector();

  @override
  String protect(String plain) => 'plain:$plain';

  @override
  String unprotect(String stored) =>
      stored.startsWith('plain:') ? stored.substring(6) : throw const FormatException('Secret illisible');
}

/// Windows DPAPI (`CryptProtectData`, portée utilisateur).
class DpapiProtector implements SecretProtector {
  static const _prefix = 'dpapi:';
  static const _uiForbidden = 0x1;

  @override
  String protect(String plain) => _prefix + base64.encode(_run(utf8.encode(plain), encrypt: true));

  @override
  String unprotect(String stored) {
    if (!stored.startsWith(_prefix)) throw const FormatException('Secret illisible');
    return utf8.decode(_run(base64.decode(stored.substring(_prefix.length)), encrypt: false));
  }

  static Uint8List _run(List<int> data, {required bool encrypt}) {
    return using((arena) {
      final input = arena<_Blob>();
      final output = arena<_Blob>();
      final buffer = arena<Uint8>(data.isEmpty ? 1 : data.length);
      buffer.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buffer;
      final ok = encrypt
          ? _protect(input, nullptr, nullptr, nullptr, nullptr, _uiForbidden, output)
          : _unprotect(input, nullptr, nullptr, nullptr, nullptr, _uiForbidden, output);
      if (ok == 0) throw StateError('DPAPI a échoué');
      try {
        return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      } finally {
        _localFree(output.ref.pbData.cast());
      }
    });
  }
}

final class _Blob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(
    Pointer<_Blob>, Pointer, Pointer<_Blob>, Pointer, Pointer, Uint32, Pointer<_Blob>);
typedef _CryptDart = int Function(
    Pointer<_Blob>, Pointer, Pointer<_Blob>, Pointer, Pointer, int, Pointer<_Blob>);

final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _protect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
final _unprotect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptUnprotectData');
final _localFree =
    _kernel32.lookupFunction<Pointer Function(Pointer), Pointer Function(Pointer)>('LocalFree');
