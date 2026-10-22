import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';

/// Contratto per acquistare/controllare lo sblocco a pagamento. La regola
/// di validità (per quanto dura) vive lato server (`PaywallStore` in
/// `server/`), non qui: il client si limita a chiedere/dichiarare, mai a
/// calcolare da solo usando il proprio orologio.
abstract class PaywallRepository {
  /// Quanto resta dello sblocco secondo l'orologio del server
  /// (`Duration.zero` se non c'è o non vale più).
  Future<Either<Failure, Duration>> getUnlockTimeRemaining();

  /// Registra un nuovo sblocco e ritorna quanto resta (secondo il server,
  /// quindi praticamente le 2 ore intere).
  ///
  /// **Finto per ora**: nessun pagamento vero avviene qui — vedi
  /// `PurchaseUnlockUseCase`.
  Future<Either<Failure, Duration>> purchaseUnlock();
}
