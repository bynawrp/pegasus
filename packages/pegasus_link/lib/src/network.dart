import 'dart:io';

/// Vrai si [address] appartient au réseau local (spec §1) : loopback,
/// RFC 1918, link-local IPv4/IPv6, IPv6 ULA (et IPv4 mappées en IPv6).
bool isLocalNetworkAddress(InternetAddress address) {
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) return _isLocalV4(raw);
  if (address.type != InternetAddressType.IPv6 || raw.length != 16) return false;

  // ::ffff:a.b.c.d
  final mapped = raw.sublist(0, 10).every((b) => b == 0) && raw[10] == 0xff && raw[11] == 0xff;
  if (mapped) return _isLocalV4(raw.sublist(12));
  if (address.isLoopback) return true;
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true; // fe80::/10
  if ((raw[0] & 0xfe) == 0xfc) return true; // fc00::/7
  return false;
}

bool _isLocalV4(List<int> b) {
  if (b.length != 4) return false;
  return b[0] == 127 ||
      b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254);
}

/// Adresses IPv4 locales de cette machine, la plus probable en premier
/// (192.168.x avant 10.x et 172.16-31.x, link-local en dernier).
Future<List<String>> localIPv4Addresses() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final addresses = [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && isLocalNetworkAddress(a)) a.address,
  ];
  int rank(String a) => a.startsWith('192.168.')
      ? 0
      : a.startsWith('10.')
          ? 1
          : a.startsWith('169.254.')
              ? 3
              : 2;
  addresses.sort((a, b) => rank(a).compareTo(rank(b)));
  return addresses;
}
