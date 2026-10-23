/// A che punto è il permesso di posizione di sistema, letto **senza**
/// chiederlo (vedi `LocationRepository.checkPermission`).
enum LocationPermissionStatus {
  /// Concesso (su Android "mentre usi l'app", su iOS "quando usi l'app" o
  /// "sempre"): basta per tutta la sessione.
  granted,

  /// Non ancora chiesto, o negato una volta: il sistema può ancora
  /// mostrare la richiesta.
  denied,

  /// Negato in modo che il sistema non mostri più la richiesta: si concede
  /// solo dalle impostazioni.
  deniedForever,
}
