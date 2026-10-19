import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/chat/domain/usecases/delete_conversation_usecase.dart';
import '../repositories/encounter_repository.dart';

/// Azione: termina volontariamente un match attivo (irreversibile).
/// Compone `DeleteConversationUseCase` (feature `chat`) come sotto-passo
/// genuino: la chat con questa persona non deve sopravvivere alla fine
/// del match.
///
/// Attende e propaga l'esito: `Left(ConnectionFailure)` se la fine non è
/// potuta partire verso il server (offline) — in quel caso il match **non**
/// è finito e la chat resta; `Right` se è partita. La cancellazione della
/// chat (solo in memoria) è best-effort e non cambia l'esito: il match è
/// comunque chiuso sul server.
class EndMatchUseCase {
  const EndMatchUseCase(this._repository, this._deleteConversationUseCase);

  final EncounterRepository _repository;
  final DeleteConversationUseCase _deleteConversationUseCase;

  Future<Either<Failure, Unit>> call({
    required String requestId,
    required String otherPersonId,
  }) async {
    final sent = _repository.endMatch(requestId);
    if (sent.isLeft()) return sent;

    await _deleteConversationUseCase(otherPersonId);
    return const Right(unit);
  }
}
