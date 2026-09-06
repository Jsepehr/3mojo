/// Contratto verso il backend `server/`: registra/controlla lo sblocco a
/// pagamento con l'ora **del server**, non quella del client — un client
/// non può falsificare l'ora del server cambiando l'orologio del proprio
/// telefono, a differenza di quanto succederebbe calcolando le 2 ore in
/// locale.
abstract class PaywallRemoteDataSource {
  /// `POST /paywall/purchase` — registra un nuovo sblocco per `deviceId`.
  Future<void> purchase(String deviceId);

  /// `GET /paywall/status` — lo sblocco di `deviceId` è ancora valido?
  Future<bool> getStatus(String deviceId);
}
