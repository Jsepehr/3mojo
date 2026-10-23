import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/location_disclosure.dart';
import '../entities/location_permission_status.dart';
import '../repositories/location_repository.dart';

/// Azione: decide se, prima di andare online, va mostrato l'avviso in
/// evidenza sulla posizione (Google Play, "prominent disclosure") e con
/// quale contenuto. Regola: **sempre, finché il permesso di posizione non è
/// concesso** — prima della prima richiesta e a ogni Start successivo in
/// cui manca ancora (negato, o tolto dalle impostazioni); mai dopo che è
/// concesso. Lo stato si legge **senza** chiedere il permesso.
///
/// Ritorna l'avviso da mostrare, o `null` se non serve. Se lo stato non si
/// può leggere, nel dubbio l'avviso si mostra: costa un tap, e la richiesta
/// di sistema non parte mai senza.
class GetLocationDisclosureUseCase
    implements UseCase<LocationDisclosure?, NoParams> {
  const GetLocationDisclosureUseCase(this._repository);

  final LocationRepository _repository;

  @override
  Future<Either<Failure, LocationDisclosure?>> call(NoParams params) async {
    final status = await _repository.checkPermission();
    final granted = status.match(
      (_) => false,
      (status) => status == LocationPermissionStatus.granted,
    );
    if (granted) return const Right(null);
    return Right(
      LocationDisclosure(
        continuesInBackground: _repository.keepsTrackingInBackground,
      ),
    );
  }
}
