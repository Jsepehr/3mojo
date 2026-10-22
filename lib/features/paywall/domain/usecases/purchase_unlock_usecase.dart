import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/unlock_status.dart';
import '../repositories/paywall_repository.dart';
import 'resolve_unlock_expiry_usecase.dart';

/// Azione: acquista lo sblocco (2 ore dal momento in cui il server lo
/// registra — vedi `GetUnlockStatusUseCase`) e ritorna fino a quando vale,
/// ricavato dal residuo detto dal server (`ResolveUnlockExpiryUseCase`).
///
/// **Finto per ora**: nessun pagamento vero avviene qui — Apple/Google
/// richiedono di passare dai loro sistemi di acquisto in-app per sbloccare
/// contenuto digitale, che vanno registrati in App Store Connect/Play
/// Console prima di poter essere integrati. Quando ci sarà un prodotto
/// reale, la vera chiamata a `in_app_purchase` andrà qui (e solo se quella
/// va a buon fine si chiama `_repository.purchaseUnlock()`) — il resto
/// dell'app (provider, UI) non cambia.
class PurchaseUnlockUseCase implements UseCase<UnlockStatus, NoParams> {
  PurchaseUnlockUseCase(
    this._repository, {
    ResolveUnlockExpiryUseCase? resolveUnlockExpiryUseCase,
  }) : _resolveUnlockExpiryUseCase =
           resolveUnlockExpiryUseCase ?? ResolveUnlockExpiryUseCase();

  final PaywallRepository _repository;
  final ResolveUnlockExpiryUseCase _resolveUnlockExpiryUseCase;

  @override
  Future<Either<Failure, UnlockStatus>> call(NoParams params) async =>
      (await _repository.purchaseUnlock()).map(
        _resolveUnlockExpiryUseCase.call,
      );
}
