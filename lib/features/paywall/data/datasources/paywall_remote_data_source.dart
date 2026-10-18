/// Uno sblocco appena comprato: il token emesso dal server e per quanto
/// vale (deciso dal server, non dal client).
typedef UnlockGrant = ({String token, Duration validFor});

/// Contratto verso il backend `server/`: registra/controlla lo sblocco a
/// pagamento con l'ora **del server**, non quella del client — un client
/// non può falsificare l'ora del server cambiando l'orologio del proprio
/// telefono, a differenza di quanto succederebbe calcolando le 2 ore in
/// locale.
abstract class PaywallRemoteDataSource {
  /// `POST /paywall/purchase` — registra un nuovo sblocco e ritorna il token
  /// che lo rappresenta.
  Future<UnlockGrant> purchase();

  /// `POST /paywall/status` — lo sblocco rappresentato da [unlockToken] è
  /// ancora valido?
  Future<bool> getStatus(String unlockToken);
}
