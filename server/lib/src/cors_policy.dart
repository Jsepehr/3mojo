import 'dart:io';

/// Gli header CORS delle risposte.
///
/// Servono solo al client Flutter **web** in sviluppo (`flutter run -d
/// chrome` gira su un'origine diversa dal server): le app Android/iOS non
/// applicano la same-origin policy. Quindi:
/// - **sviluppo** (default): `Access-Control-Allow-Origin: *`;
/// - **production** (`RAEN_ENV=production`): **nessun** header CORS, il
///   browser blocca le chiamate da altre origini — a meno che
///   `CORS_ALLOW_ORIGIN` elenchi origini precise (separate da virgola, es.
///   `https://raen.example`): allora solo quelle, riecheggiate come
///   `Access-Control-Allow-Origin` con `Vary: Origin`.
/// - `CORS_ALLOW_ORIGIN=*` forza il vecchio comportamento in qualunque
///   ambiente (sconsigliato in production), `CORS_ALLOW_ORIGIN=none` lo
///   spegne.
///
/// `Authorization` non è mai tra gli header ammessi: gli endpoint admin non
/// si chiamano da un browser su un'altra origine.
class CorsPolicy {
  const CorsPolicy._({this.allowAny = false, this.origins = const {}});

  factory CorsPolicy.fromEnvironment(Map<String, String> environment) {
    final raw = (environment['CORS_ALLOW_ORIGIN'] ?? '').trim();
    final production =
        (environment['RAEN_ENV'] ?? '').trim().toLowerCase() == 'production';
    if (raw.isEmpty) {
      return production
          ? const CorsPolicy._()
          : const CorsPolicy._(allowAny: true);
    }
    if (raw == '*') return const CorsPolicy._(allowAny: true);
    if (raw.toLowerCase() == 'none') return const CorsPolicy._();
    return CorsPolicy._(
      origins: {
        for (final origin in raw.split(','))
          if (origin.trim().isNotEmpty) origin.trim(),
      },
    );
  }

  static final CorsPolicy instance = CorsPolicy.fromEnvironment(
    Platform.environment,
  );

  final bool allowAny;
  final Set<String> origins;

  /// Gli header per una richiesta con `Origin: [origin]` (può essere
  /// `null`). Vuoti se l'origine non è ammessa.
  Map<String, String> headersFor(String? origin) {
    final String allowed;
    if (allowAny) {
      allowed = '*';
    } else if (origin != null && origins.contains(origin)) {
      allowed = origin;
    } else {
      return const {};
    }
    return {
      'Access-Control-Allow-Origin': allowed,
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
      // `Authorization` non c'è apposta (vedi la doc della classe).
      'Access-Control-Allow-Headers': 'Content-Type, X-Raen-Protocol',
      if (!allowAny) 'Vary': 'Origin',
    };
  }
}
