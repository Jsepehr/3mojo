import '/features/chat/domain/usecases/delete_conversation_usecase.dart';
import '../repositories/encounter_repository.dart';

/// Azione: termina volontariamente un match attivo (irreversibile) —
/// fire-and-forget. Compone `DeleteConversationUseCase` (feature `chat`)
/// come sotto-passo genuino: la chat con questa persona non deve
/// sopravvivere alla fine del match.
class EndMatchUseCase {
  const EndMatchUseCase(this._repository, this._deleteConversationUseCase);

  final EncounterRepository _repository;
  final DeleteConversationUseCase _deleteConversationUseCase;

  void call({required String requestId, required String otherPersonId}) {
    _repository.endMatch(requestId);
    _deleteConversationUseCase(otherPersonId);
  }
}
