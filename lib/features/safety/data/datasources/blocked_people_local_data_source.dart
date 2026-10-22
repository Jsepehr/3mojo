/// Contratto per lo stato di sicurezza **della sessione in corso** sul
/// telefono: chi hai bloccato (pseudonimi) e quante segnalazioni hai
/// mandato. Solo in memoria, mai su disco: gli pseudonimi valgono solo per
/// questa sessione e il blocco vero lo tiene il server.
abstract class BlockedPeopleLocalDataSource {
  Set<String> get blockedPersonIds;

  /// Subito l'insieme attuale, poi a ogni cambiamento.
  Stream<Set<String>> watchBlockedPersonIds();

  void addBlocked(String personId);

  int get reportsSent;

  void incrementReportsSent();

  /// Svuota tutto (End).
  void clear();
}
