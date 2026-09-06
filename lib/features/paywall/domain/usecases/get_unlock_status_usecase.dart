import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/paywall_repository.dart';

/// Azione: lo sblocco a pagamento è ancora valido? La regola di validità
/// (2 ore) è decisa e calcolata dal server (`PaywallStore`), non qui —
/// questo use case si limita a chiedere, mai a fare i conti da solo con
/// l'orologio del telefono (falsificabile dall'utente).
class GetUnlockStatusUseCase implements UseCase<bool, NoParams> {
  const GetUnlockStatusUseCase(this._repository);

  final PaywallRepository _repository;

  @override
  Future<Either<Failure, bool>> call(NoParams params) =>
      _repository.isUnlocked();
}
