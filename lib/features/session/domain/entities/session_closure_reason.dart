/// Perché il server ha chiuso la sessione per conto suo
/// (`{"type": "sessionClosed", "reason": ...}`).
enum SessionClosureReason {
  /// Abbastanza persone diverse l'hanno segnalata: nuovi Start da questa
  /// rete in pausa per un po'.
  reports,

  /// Il server si sta riavviando (deploy): nessuna colpa, si può ripartire
  /// subito con un nuovo Start.
  serverRestart;

  /// Dal motivo scritto sul filo; un motivo sconosciuto (server più nuovo)
  /// o assente vale [reports], l'unico che esisteva prima.
  static SessionClosureReason fromWire(String? reason) => switch (reason) {
    'serverRestart' => serverRestart,
    _ => reports,
  };
}
