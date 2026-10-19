/// In che stato è il canale in tempo reale col server per la sessione
/// corrente — quanto basta alla UI per dire "connessione persa, mi sto
/// riconnettendo" senza svuotare ciò che sta mostrando.
enum ConnectionStatus {
  /// Nessuna sessione collegata (offline, o dopo End).
  offline,

  /// Primo collegamento della sessione in corso.
  connecting,

  /// Collegati: le azioni partono davvero.
  online,

  /// Il collegamento è caduto e si sta riprovando da soli.
  reconnecting,
}
