import 'dart:io';

import 'package:threemojo_server/src/rate_limiters.dart';

/// Limita quante **nuove** sessioni può aprire lo stesso indirizzo IP in una
/// finestra di tempo. Le riconnessioni di una sessione già viva non contano.
///
/// Perché: con il matching reciproco, il solo fatto di vedere qualcuno in
/// lista dice che cerca persone come te. Chi volesse scoprire la preferenza
/// di una persona potrebbe rifare Start più volte dichiarando generi
/// diversi e guardare quando compare. Il genere è già fissato per tutta la
/// sessione (`Session.profile`); questo limite rende lento e visibile anche
/// il ripetere lo Start.
///
/// Solo in RAM: per ogni IP si tengono gli orari degli ultimi Start, e solo
/// per la durata della finestra (vedi [SlidingWindowRateLimiter]). Dietro un
/// reverse proxy l'IP va risolto con `resolveClientIp` (`TRUSTED_PROXY`),
/// altrimenti tutti i client sembrerebbero lo stesso IP, quello del proxy.
class NewSessionRateLimiter {
  NewSessionRateLimiter._({DateTime Function()? now, int? limit})
    : limit = limit ?? maxNewSessions,
      _limiter = SlidingWindowRateLimiter(
        maxActions: limit ?? maxNewSessions,
        window: window,
        now: now,
      );

  /// Solo per i test: orologio controllabile (e, volendo, un altro limite).
  factory NewSessionRateLimiter.withClock(
    DateTime Function() now, {
    int limit = maxNewSessions,
  }) => NewSessionRateLimiter._(now: now, limit: limit);

  static final NewSessionRateLimiter instance = NewSessionRateLimiter._(
    limit: limitFromEnvironment(Platform.environment),
  );

  /// Volutamente non basso: molte persone diverse possono condividere lo
  /// stesso IP (Wi-Fi di un locale, CGNAT degli operatori mobili) e non
  /// devono bloccarsi a vicenda. Basta a rendere lento il sondaggio
  /// ripetuto, non a impedirlo del tutto. È il valore predefinito: si può
  /// cambiare con [limitEnvironmentVariable].
  static const maxNewSessions = 20;
  static const window = Duration(minutes: 10);

  /// Variabile d'ambiente che sostituisce [maxNewSessions] (intero > 0). Per
  /// le prove in locale: `tool/simulate_fake_devices.dart` apre da solo 20
  /// sessioni dallo stesso IP, cioè tutto il limite predefinito.
  static const limitEnvironmentVariable = 'MAX_NEW_SESSIONS_PER_IP';

  /// Il limite letto da [environment] ([limitEnvironmentVariable]), o
  /// [maxNewSessions] se manca o non è un intero positivo.
  static int limitFromEnvironment(Map<String, String> environment) {
    final parsed = int.tryParse(
      environment[limitEnvironmentVariable]?.trim() ?? '',
    );
    return parsed != null && parsed > 0 ? parsed : maxNewSessions;
  }

  /// Quanti nuovi Start per IP sono ammessi in [window].
  final int limit;

  final SlidingWindowRateLimiter _limiter;

  /// Registra un nuovo Start da [ip] e dice se è consentito.
  bool tryStart(String ip) => _limiter.tryAcquire(ip);
}
