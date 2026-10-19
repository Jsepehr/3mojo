import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../repositories/selfie_repository.dart';
import 'session_teardown_usecase.dart';

/// Azione: nessun file del selfie resta sul telefono dopo End. Ogni scatto
/// viene già cancellato appena letto; questo passo ripulisce ciò che fosse
/// rimasto (es. app chiusa a metà scatto). È uno dei passi di pulizia di
/// `EndSessionUseCase` (contratto [SessionTeardownUseCase]); l'id della
/// sessione non serve.
class DiscardSelfieFilesUseCase implements SessionTeardownUseCase {
  const DiscardSelfieFilesUseCase(this._repository);

  final SelfieRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String sessionId) =>
      _repository.discardLeftoverFiles();
}
