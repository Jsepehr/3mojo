import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/store_purchase.dart';

/// Contratto per riscattare/controllare lo sblocco a pagamento sul server.
/// La regola di validità (per quanto dura) e la verifica del pagamento col
/// negozio vivono lato server (`PaywallStore`, `UnlockPurchaseService` in
/// `server/`), non qui: il client si limita a chiedere/dichiarare, mai a
/// calcolare da solo usando il proprio orologio.
abstract class PaywallRepository {
  /// Quanto resta dello sblocco secondo l'orologio del server
  /// (`Duration.zero` se non c'è o non vale più).
  Future<Either<Failure, Duration>> getUnlockTimeRemaining();

  /// Manda l'acquisto al server, che lo verifica col negozio e, se valido,
  /// emette lo sblocco (salvato sul telefono). Ritorna quanto resta secondo
  /// il server. Errori: `PurchaseNotVerifiedFailure` (il negozio dice che
  /// non vale), `PurchaseAlreadyRedeemedFailure`, `ConnectionFailure`
  /// (server non raggiungibile o non ha potuto verificare: riprovare).
  ///
  /// Idempotente: la stessa transazione riscattata di nuovo ridà lo stesso
  /// sblocco finché vale.
  Future<Either<Failure, Duration>> redeemPurchase(StorePurchase purchase);
}
