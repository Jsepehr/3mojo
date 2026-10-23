import '../models/store_purchase_model.dart';

/// Uno sblocco appena riscattato: il token emesso dal server e quanto resta
/// (deciso dal server, non dal client).
typedef UnlockGrant = ({String token, Duration remaining});

/// Contratto verso il backend `server/`: registra/controlla lo sblocco a
/// pagamento con l'ora **del server**, non quella del client — un client
/// non può falsificare l'ora del server cambiando l'orologio del proprio
/// telefono, a differenza di quanto succederebbe calcolando le 2 ore in
/// locale.
abstract class PaywallRemoteDataSource {
  /// `POST /paywall/purchase` — manda l'acquisto del negozio; il server lo
  /// verifica col negozio e, se vale, ritorna il token dello sblocco
  /// (lo stesso, se la transazione era già stata riscattata e vale ancora).
  ///
  /// Lancia `PurchaseRejectedException` (422: il negozio dice che non
  /// vale), `PurchaseAlreadyRedeemedException` (409) o `ServerException`
  /// (rete, 5xx, risposta non valida: si riprova).
  Future<UnlockGrant> redeemPurchase(StorePurchaseModel purchase);

  /// `POST /paywall/status` — quanto resta dello sblocco rappresentato da
  /// [unlockToken], sull'orologio del server (`Duration.zero` se non vale
  /// più).
  Future<Duration> getRemaining(String unlockToken);
}
