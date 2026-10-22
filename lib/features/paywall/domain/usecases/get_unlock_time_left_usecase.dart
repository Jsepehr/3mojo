import '../entities/unlock_status.dart';
import '../entities/unlock_time_left.dart';

/// Azione: quanto resta, da mostrare, di uno sblocco — o `null` se non c'è
/// o è già scaduto (allora il chip sparisce e torna il banner d'acquisto).
///
/// Regole:
/// - si mostrano **minuti interi per difetto**, mai i secondi: con 1 h 42 min
///   30 s restanti "1 h 42 min"; nell'ultimo minuto `wholeMinutes == 0`
///   ("meno di un minuto");
/// - il valore cambia sul confine del minuto ([UnlockTimeLeft.nextChangeIn]:
///   esattamente quando i minuti interi scendono di uno, o alla scadenza),
///   così un solo timer per minuto basta e nessun aggiornamento arriva in
///   ritardo;
/// - "sta per finire" negli ultimi [endingSoonThreshold] (10 minuti).
///
/// Puro (nessun I/O), con l'orologio iniettabile per i test.
class GetUnlockTimeLeftUseCase {
  GetUnlockTimeLeftUseCase({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const endingSoonThreshold = Duration(minutes: 10);

  final DateTime Function() _now;

  UnlockTimeLeft? call(UnlockStatus status) {
    final expiresAt = status.expiresAt;
    if (expiresAt == null) return null;
    final remaining = expiresAt.difference(_now());
    if (remaining <= Duration.zero) return null;

    // Minuti interi *strettamente* oltre quello in corso: a 42 min esatti si
    // mostra già 41, così il prossimo cambio è sempre nel futuro (mai un
    // timer da 0) e l'ultimo cade esattamente sulla scadenza.
    final wholeMinutes =
        (remaining.inMicroseconds - 1) ~/ Duration.microsecondsPerMinute;
    return UnlockTimeLeft(
      wholeMinutes: wholeMinutes,
      isEndingSoon: remaining <= endingSoonThreshold,
      nextChangeIn: remaining - Duration(minutes: wholeMinutes),
    );
  }
}
