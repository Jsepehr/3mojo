import 'dart:io';

import 'package:threemojo_server/src/ip_address.dart';

/// I proxy fidati, da `TRUSTED_PROXY` (IP separati da virgola, es.
/// `127.0.0.1,10.0.0.5`): solo per connessioni che arrivano **da uno di
/// questi** si legge `X-Forwarded-For`. Vuoto (il default) = nessun proxy:
/// l'header viene ignorato, perché chiunque altro potrebbe scriverci un IP
/// a caso per aggirare i limiti per IP. Gli indirizzi sono normalizzati
/// ([normalizeIp]): `::ffff:127.0.0.1` e `127.0.0.1` sono lo stesso proxy.
Set<String> trustedProxiesFromEnvironment([Map<String, String>? environment]) {
  final raw = (environment ?? Platform.environment)['TRUSTED_PROXY'] ?? '';
  return {
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) normalizeIp(part),
  };
}

/// L'IP del client vero, per i limiti per IP (`NewSessionRateLimiter`,
/// `purchaseRateLimiter`).
///
/// Senza proxy fidati è l'indirizzo della connessione. Se la connessione
/// arriva da un proxy fidato, è l'ultimo indirizzo di `X-Forwarded-For` che
/// **non** è a sua volta un proxy fidato (i proxy aggiungono in coda: gli
/// elementi più a sinistra li ha scritti il client e non valgono nulla).
String resolveClientIp({
  required String remoteAddress,
  required String? forwardedFor,
  required Set<String> trustedProxies,
}) {
  final remote = normalizeIp(remoteAddress);
  final trusted = {for (final proxy in trustedProxies) normalizeIp(proxy)};
  if (!trusted.contains(remote)) return remote;
  if (forwardedFor == null || forwardedFor.trim().isEmpty) return remote;

  final hops = forwardedFor
      .split(',')
      .map(normalizeIp)
      .where((hop) => hop.isNotEmpty)
      .toList();
  for (final hop in hops.reversed) {
    if (!trusted.contains(hop)) return hop;
  }
  return remote;
}
