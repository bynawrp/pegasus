import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';

import '../input_controller.dart';

/// Évènement élémentaire envoyé à Windows (`SendInput`).
sealed class RawInput {
  const RawInput();
}

class RawMouse extends RawInput {
  const RawMouse({this.dx = 0, this.dy = 0, this.flags = 0, this.data = 0});
  final int dx;
  final int dy;
  final int flags;
  final int data;

  @override
  bool operator ==(Object other) =>
      other is RawMouse && other.dx == dx && other.dy == dy && other.flags == flags && other.data == data;
  @override
  int get hashCode => Object.hash(dx, dy, flags, data);
  @override
  String toString() => 'mouse($dx,$dy,0x${flags.toRadixString(16)},$data)';
}

class RawKey extends RawInput {
  const RawKey({this.vk = 0, this.scan = 0, this.flags = 0});
  final int vk;
  final int scan;
  final int flags;

  bool get up => flags & WinInput.keyUp != 0;

  @override
  bool operator ==(Object other) => other is RawKey && other.vk == vk && other.scan == scan && other.flags == flags;
  @override
  int get hashCode => Object.hash(vk, scan, flags);
  @override
  String toString() => 'key(vk:0x${vk.toRadixString(16)},scan:$scan,0x${flags.toRadixString(16)})';
}

/// Constantes Win32 utilisées.
abstract final class WinInput {
  static const mouse = 0;
  static const keyboard = 1;

  static const move = 0x0001;
  static const leftDown = 0x0002, leftUp = 0x0004;
  static const rightDown = 0x0008, rightUp = 0x0010;
  static const middleDown = 0x0020, middleUp = 0x0040;
  static const wheel = 0x0800, hWheel = 0x1000;
  static const wheelDelta = 120;

  static const extended = 0x0001, keyUp = 0x0002, unicode = 0x0004;

  static const vkShift = 0x10, vkControl = 0x11, vkMenu = 0x12, vkLWin = 0x5B, vkReturn = 0x0D, vkTab = 0x09;

  /// Codes des touches nommées du protocole ; `true` = touche « étendue ».
  static final Map<String, (int, bool)> keys = {
    'escape': (0x1B, false),
    'tab': (0x09, false),
    'enter': (0x0D, false),
    'backspace': (0x08, false),
    'delete': (0x2E, true),
    'space': (0x20, false),
    'up': (0x26, true),
    'down': (0x28, true),
    'left': (0x25, true),
    'right': (0x27, true),
    'home': (0x24, true),
    'end': (0x23, true),
    'pageup': (0x21, true),
    'pagedown': (0x22, true),
    'printscreen': (0x2C, true),
    'win': (0x5B, true),
    for (var i = 1; i <= 12; i++) 'f$i': (0x6F + i, false),
    for (var c = 0; c < 26; c++) String.fromCharCode(0x61 + c): (0x41 + c, false),
    for (var d = 0; d <= 9; d++) '$d': (0x30 + d, false),
  };

  static (int, bool) modifier(KeyModifier m) => switch (m) {
        KeyModifier.ctrl => (vkControl, false),
        KeyModifier.alt => (vkMenu, false),
        KeyModifier.shift => (vkShift, false),
        KeyModifier.win => (vkLWin, true),
      };
}

/// Traduit les opérations du protocole en évènements `SendInput` (pur, testé).
class WindowsInputPlanner {
  double _restX = 0, _restY = 0;
  double _wheelX = 0, _wheelY = 0;

  List<RawInput> move(double dx, double dy) {
    _restX += dx;
    _restY += dy;
    final x = _restX.truncate();
    final y = _restY.truncate();
    _restX -= x;
    _restY -= y;
    if (x == 0 && y == 0) return const [];
    return [RawMouse(dx: x, dy: y, flags: WinInput.move)];
  }

  List<RawInput> scroll(double dx, double dy) {
    // Windows : molette positive = vers le haut ; protocole : dy > 0 = vers le bas.
    _wheelY += -dy * WinInput.wheelDelta;
    _wheelX += dx * WinInput.wheelDelta;
    final y = _wheelY.truncate();
    final x = _wheelX.truncate();
    _wheelY -= y;
    _wheelX -= x;
    return [
      if (y != 0) RawMouse(flags: WinInput.wheel, data: y),
      if (x != 0) RawMouse(flags: WinInput.hWheel, data: x),
    ];
  }

  List<RawInput> button(MouseButton b, {required bool down}) {
    final flags = switch ((b, down)) {
      (MouseButton.left, true) => WinInput.leftDown,
      (MouseButton.left, false) => WinInput.leftUp,
      (MouseButton.right, true) => WinInput.rightDown,
      (MouseButton.right, false) => WinInput.rightUp,
      (MouseButton.middle, true) => WinInput.middleDown,
      (MouseButton.middle, false) => WinInput.middleUp,
    };
    return [RawMouse(flags: flags)];
  }

  List<RawInput> click(MouseButton b, {int count = 1}) => [
        for (var i = 0; i < count; i++) ...[...button(b, down: true), ...button(b, down: false)],
      ];

  List<RawInput> text(String text) {
    final out = <RawInput>[];
    final units = text.replaceAll('\r\n', '\n').codeUnits;
    for (final u in units) {
      if (u == 0x0A || u == 0x0D) {
        out.addAll(_tap(WinInput.vkReturn, false));
      } else if (u == 0x09) {
        out.addAll(_tap(WinInput.vkTab, false));
      } else {
        out
          ..add(RawKey(scan: u, flags: WinInput.unicode))
          ..add(RawKey(scan: u, flags: WinInput.unicode | WinInput.keyUp));
      }
    }
    return out;
  }

  List<RawInput> key(String key, List<KeyModifier> modifiers, {int repeat = 1}) {
    final target = WinInput.keys[key];
    if (target == null) return const [];
    final mods = modifiers.map(WinInput.modifier).toList();
    return [
      for (final (vk, ext) in mods) _key(vk, ext, up: false),
      for (var i = 0; i < repeat; i++) ..._tap(target.$1, target.$2),
      for (final (vk, ext) in mods.reversed) _key(vk, ext, up: true),
    ];
  }

  List<RawInput> _tap(int vk, bool ext) => [_key(vk, ext, up: false), _key(vk, ext, up: true)];

  RawKey _key(int vk, bool ext, {required bool up}) =>
      RawKey(vk: vk, flags: (ext ? WinInput.extended : 0) | (up ? WinInput.keyUp : 0));
}

// --- FFI : user32!SendInput ---

final class MOUSEINPUT extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class KEYBDINPUT extends Struct {
  @Uint16()
  external int wVk;
  @Uint16()
  external int wScan;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class InputUnion extends Union {
  external MOUSEINPUT mi;
  external KEYBDINPUT ki;
}

final class INPUT extends Struct {
  @Uint32()
  external int type;
  external InputUnion u;
}

typedef _SendInputNative = Uint32 Function(Uint32, Pointer<INPUT>, Int32);
typedef _SendInputDart = int Function(int, Pointer<INPUT>, int);

/// Implémentation Windows via `SendInput`.
///
/// Limite connue : Windows bloque l'injection vers les fenêtres lancées en
/// administrateur si l'agent ne l'est pas (UIPI).
class WindowsInputController implements InputController {
  WindowsInputController() : _send = DynamicLibrary.open('user32.dll').lookupFunction<_SendInputNative, _SendInputDart>('SendInput');

  final _SendInputDart _send;
  final planner = WindowsInputPlanner();

  /// Envoie les évènements ; renvoie le nombre accepté par Windows.
  int dispatch(List<RawInput> events) {
    if (events.isEmpty) return 0;
    final buffer = calloc<INPUT>(events.length);
    try {
      for (var i = 0; i < events.length; i++) {
        final input = buffer[i];
        switch (events[i]) {
          case RawMouse(:final dx, :final dy, :final flags, :final data):
            input.type = WinInput.mouse;
            input.u.mi
              ..dx = dx
              ..dy = dy
              ..mouseData = data & 0xFFFFFFFF
              ..dwFlags = flags;
          case RawKey(:final vk, :final scan, :final flags):
            input.type = WinInput.keyboard;
            input.u.ki
              ..wVk = vk
              ..wScan = scan
              ..dwFlags = flags;
        }
      }
      return _send(events.length, buffer, sizeOf<INPUT>());
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void move(double dx, double dy) => dispatch(planner.move(dx, dy));

  @override
  void scroll(double dx, double dy) => dispatch(planner.scroll(dx, dy));

  @override
  void button(MouseButton button, {required bool down}) => dispatch(planner.button(button, down: down));

  @override
  void click(MouseButton button, {int count = 1}) => dispatch(planner.click(button, count: count));

  @override
  void text(String text) => dispatch(planner.text(text));

  @override
  void key(String key, List<KeyModifier> modifiers, {int repeat = 1}) =>
      dispatch(planner.key(key, modifiers, repeat: repeat));
}
