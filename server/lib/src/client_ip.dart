import 'dart:io';

/// I proxy fidati, da `TRUSTED_PROXY` (IP separati da virgola, es.
/// `127.0.0.1,10.0.0.5`): solo per connessioni che arrivano **da uno di
/// questi** si legge `X-Forwarded-For`. Vuoto (il default) = nessun proxy:
/// l'header viene ignorato, perché chiunque altro potrebbe scriverci un IP
/// a caso per aggirare i limiti per IP.
Set<String> trustedProxiesFromEnvironment([Map<String, String>? environment]) {
  final raw = (environment ?? Platform.environment)['TRUSTED_PROXY'] ?? '';
  return {
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
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
  if (!trustedProxies.contains(remoteAddress)) return remoteAddress;
  if (forwardedFor == null || forwardedFor.trim().isEmpty) return remoteAddress;

  final hops = forwardedFor
      .split(',')
      .map((hop) => hop.trim())
      .where((hop) => hop.isNotEmpty)
      .toList();
  for (final hop in hops.reversed) {
    if (!trustedProxies.contains(hop)) return hop;
  }
  return remoteAddress;
}
