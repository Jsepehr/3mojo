import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/domain/usecases/session_teardown_usecase.dart';
import '../repositories/chat_repository.dart';

/// Azione: dimentica tutte le chat della sessione appena finita. È uno dei
/// passi di pulizia di End (`EndSessionUseCase`, tramite il contratto
/// [SessionTeardownUseCase]): la cronologia vive solo in memoria e non
/// deve sopravvivere alla sessione.
class ClearChatSessionUseCase implements SessionTeardownUseCase {
  const ClearChatSessionUseCase(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(String endingSessionId) =>
      _repository.clearSessionState();
}
