import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/paywall_repository.dart';

/// Azione: acquista lo sblocco (2 ore dal momento in cui il server lo
/// registra — vedi `GetUnlockStatusUseCase`).
///
/// **Finto per ora**: nessun pagamento vero avviene qui — Apple/Google
/// richiedono di passare dai loro sistemi di acquisto in-app per sbloccare
/// contenuto digitale, che vanno registrati in App Store Connect/Play
/// Console prima di poter essere integrati. Quando ci sarà un prodotto
/// reale, la vera chiamata a `in_app_purchase` andrà qui (e solo se quella
/// va a buon fine si chiama `_repository.purchaseUnlock()`) — il resto
/// dell'app (provider, UI) non cambia.
class PurchaseUnlockUseCase implements UseCase<Unit, NoParams> {
  const PurchaseUnlockUseCase(this._repository);

  final PaywallRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.purchaseUnlock();
}
