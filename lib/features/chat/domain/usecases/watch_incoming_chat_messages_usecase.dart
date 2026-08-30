import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

/// Azione: resta in ascolto dei messaggi in arrivo da `otherPersonId` sulla
/// connessione condivisa — spinti appena arrivano, non richiesti con un
/// polling. Compone `GetCurrentSessionUseCase` per sapere chi sono, come
/// `WatchNearbyPeopleUseCase`/`WatchEncounterRequestsUseCase`.
class WatchIncomingChatMessagesUseCase {
  const WatchIncomingChatMessagesUseCase({
    required GetCurrentSessionUseCase getCurrentSessionUseCase,
    required ChatRepository repository,
  }) : _getCurrentSessionUseCase = getCurrentSessionUseCase,
       _repository = repository;

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;
  final ChatRepository _repository;

  Stream<Either<Failure, ChatMessage>> call(String otherPersonId) async* {
    final sessionResult = await _getCurrentSessionUseCase(const NoParams());

    Failure? failure;
    final sessionId = sessionResult.match((f) {
      failure = f;
      return null;
    }, (session) => session?.sessionId);

    if (failure != null) {
      yield Left(failure!);
      return;
    }
    if (sessionId == null) {
      yield const Left(ValidationFailure('Devi essere online per chattare'));
      return;
    }

    yield* _repository.watchIncomingMessages(
      sessionId: sessionId,
      otherPersonId: otherPersonId,
    );
  }
}
