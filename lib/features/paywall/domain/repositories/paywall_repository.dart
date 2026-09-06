import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';

/// Contratto per acquistare/controllare lo sblocco a pagamento. La regola
/// di validità (per quanto dura) vive lato server (`PaywallStore` in
/// `server/`), non qui: il client si limita a chiedere/dichiarare, mai a
/// calcolare da solo usando il proprio orologio.
abstract class PaywallRepository {
  Future<Either<Failure, bool>> isUnlocked();

  /// **Finto per ora**: nessun pagamento vero avviene qui — vedi
  /// `PurchaseUnlockUseCase`.
  Future<Either<Failure, Unit>> purchaseUnlock();
}
