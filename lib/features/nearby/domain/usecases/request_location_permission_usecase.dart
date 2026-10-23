import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/location_permission_status.dart';
import '../repositories/location_repository.dart';

/// Azione: chiede il permesso di posizione al sistema — solo dopo che
/// l'utente ha letto l'avviso in evidenza e ha scelto "Continua" (vedi
/// `GetLocationDisclosureUseCase`). Regola: **senza permesso non si va
/// online** (non si vedrebbe nessuno e nessuno ti vedrebbe): se non viene
/// concesso, `LocationPermissionFailure` e lo Start non parte.
class RequestLocationPermissionUseCase implements UseCase<Unit, NoParams> {
  const RequestLocationPermissionUseCase(this._repository);

  final LocationRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final result = await _repository.requestPermission();
    return result.flatMap(
      (status) => status == LocationPermissionStatus.granted
          ? const Right(unit)
          : Left(LocationPermissionFailure('Location permission: $status')),
    );
  }
}
