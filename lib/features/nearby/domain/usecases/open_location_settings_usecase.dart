import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/repositories/location_repository.dart';

/// Azione: porta l'utente alle impostazioni di sistema per riaccendere la
/// localizzazione — proposta quando "Vicinanze" fallisce con
/// `LocationDisabledFailure`.
class OpenLocationSettingsUseCase implements UseCase<Unit, NoParams> {
  const OpenLocationSettingsUseCase(this._repository);

  final LocationRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.openLocationSettings();
}
