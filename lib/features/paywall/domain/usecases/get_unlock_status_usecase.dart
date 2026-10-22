import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/unlock_status.dart';
import '../repositories/paywall_repository.dart';
import 'resolve_unlock_expiry_usecase.dart';

/// Azione: lo sblocco a pagamento è ancora valido, e fino a quando? La
/// regola di validità (2 ore) è decisa e calcolata dal server
/// (`PaywallStore`), non qui: il server dice quanto **resta** e
/// `ResolveUnlockExpiryUseCase` ne ricava la scadenza sul telefono — mai i
/// conti fatti da soli con l'orologio del telefono (falsificabile).
class GetUnlockStatusUseCase implements UseCase<UnlockStatus, NoParams> {
  GetUnlockStatusUseCase(
    this._repository, {
    ResolveUnlockExpiryUseCase? resolveUnlockExpiryUseCase,
  }) : _resolveUnlockExpiryUseCase =
           resolveUnlockExpiryUseCase ?? ResolveUnlockExpiryUseCase();

  final PaywallRepository _repository;
  final ResolveUnlockExpiryUseCase _resolveUnlockExpiryUseCase;

  @override
  Future<Either<Failure, UnlockStatus>> call(NoParams params) async =>
      (await _repository.getUnlockTimeRemaining()).map(
        _resolveUnlockExpiryUseCase.call,
      );
}
