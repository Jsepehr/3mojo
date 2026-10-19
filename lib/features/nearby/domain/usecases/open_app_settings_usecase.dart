import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/nearby/domain/repositories/location_repository.dart';

/// Azione: porta l'utente alla pagina di questa app nelle impostazioni di
/// sistema, per concedere di nuovo il permesso di posizione — proposta
/// quando "Vicinanze" fallisce con `LocationPermissionFailure` (un permesso
/// negato "per sempre" non si può più chiedere dall'app).
class OpenAppSettingsUseCase implements UseCase<Unit, NoParams> {
  const OpenAppSettingsUseCase(this._repository);

  final LocationRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.openAppSettings();
}
