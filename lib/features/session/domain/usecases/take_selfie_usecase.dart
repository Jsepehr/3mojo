import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/selfie_repository.dart';

/// Azione: scatta il selfie con la fotocamera frontale. `null` = annullato.
/// Il file scritto dalla fotocamera non sopravvive allo scatto (vedi
/// `SelfieLocalDataSourceImpl`): il selfie esce di qui solo come byte.
class TakeSelfieUseCase implements UseCase<Uint8List?, NoParams> {
  const TakeSelfieUseCase(this._repository);

  final SelfieRepository _repository;

  @override
  Future<Either<Failure, Uint8List?>> call(NoParams params) =>
      _repository.takeSelfie();
}
