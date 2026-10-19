import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '../repositories/chat_repository.dart';

/// Azione: resta in ascolto dei messaggi miei che il server non ha potuto
/// consegnare (id del messaggio), per mostrarli come "non inviati" invece
/// di far credere che siano arrivati. Senza sessione non emette nulla.
class WatchUndeliveredChatMessagesUseCase {
  const WatchUndeliveredChatMessagesUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required ChatRepository repository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _repository = repository;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final ChatRepository _repository;

  Stream<String> call() async* {
    final sessionResult = await _getCurrentSessionUseCase(const NoParams());
    final sessionId = sessionResult.match(
      (_) => null,
      (session) => session?.sessionId,
    );
    if (sessionId == null) return;

    yield* _repository.watchUndeliveredMessageIds(sessionId: sessionId);
  }
}
