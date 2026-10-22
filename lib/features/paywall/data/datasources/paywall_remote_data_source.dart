/// Uno sblocco appena comprato: il token emesso dal server e quanto resta
/// (deciso dal server, non dal client).
typedef UnlockGrant = ({String token, Duration remaining});

/// Contratto verso il backend `server/`: registra/controlla lo sblocco a
/// pagamento con l'ora **del server**, non quella del client — un client
/// non può falsificare l'ora del server cambiando l'orologio del proprio
/// telefono, a differenza di quanto succederebbe calcolando le 2 ore in
/// locale.
abstract class PaywallRemoteDataSource {
  /// `POST /paywall/purchase` — registra un nuovo sblocco e ritorna il token
  /// che lo rappresenta.
  Future<UnlockGrant> purchase();

  /// `POST /paywall/status` — quanto resta dello sblocco rappresentato da
  /// [unlockToken], sull'orologio del server (`Duration.zero` se non vale
  /// più).
  Future<Duration> getRemaining(String unlockToken);
}
