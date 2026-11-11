String _two(int n) => n.toString().padLeft(2, '0');

/// `14:02`
String formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// `11/11 · 14:02`, ou `aujourd'hui · 14:02`.
String formatDateTime(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = t.year == n.year && t.month == n.month && t.day == n.day;
  return '${today ? "aujourd'hui" : '${_two(t.day)}/${_two(t.month)}'} · ${formatTime(t)}';
}

/// `4:59`
String formatCountdown(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return '${s ~/ 60}:${_two(s % 60)}';
}

/// `482 193`
String formatCode(String code) =>
    code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
