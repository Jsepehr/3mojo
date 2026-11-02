import 'dart:io';

/// Porta un indirizzo IP a una forma unica, per confronti e chiavi di
/// limite: un IPv4 che arriva "mappato" in IPv6 (`::ffff:127.0.0.1`, come
/// fa un socket dual-stack) diventa l'IPv4 (`127.0.0.1`). Senza, un
/// `TRUSTED_PROXY=127.0.0.1` non riconoscerebbe il proxy locale e lo stesso
/// client avrebbe due chiavi diverse nei limiti per IP.
///
/// Un testo che non è un indirizzo (es. un valore sporco in
/// `X-Forwarded-For`) torna com'è, tagliato degli spazi: non si inventa
/// nulla, e di sicuro non coincide con un proxy fidato.
String normalizeIp(String address) {
  final trimmed = address.trim();
  final parsed = InternetAddress.tryParse(trimmed);
  if (parsed == null) return trimmed;
  if (parsed.type == InternetAddressType.IPv6) {
    final bytes = parsed.rawAddress;
    final mapped =
        bytes.length == 16 &&
        bytes.sublist(0, 10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (mapped) {
      return InternetAddress.fromRawAddress(
        bytes.sublist(12),
        type: InternetAddressType.IPv4,
      ).address;
    }
  }
  return parsed.address;
}

/// `true` se [address] (in una qualsiasi forma, anche IPv4-mapped) è un
/// indirizzo di loopback.
bool isLoopbackIp(String address) =>
    InternetAddress.tryParse(normalizeIp(address))?.isLoopback ?? false;
