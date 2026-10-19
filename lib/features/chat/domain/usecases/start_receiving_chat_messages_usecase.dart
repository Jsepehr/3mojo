import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../repositories/chat_repository.dart';

/// Azione: da quando la sessione è online, i messaggi di chat in arrivo si
/// ricevono e si tengono (solo in memoria) **anche prima** che la pagina
/// del match si apra — il partner può scrivere un istante dopo aver
/// accettato, mentre qui la pagina non c'è ancora: senza, quel messaggio
/// andrebbe perso (il server non conserva nulla).
class StartReceivingChatMessagesUseCase {
  const StartReceivingChatMessagesUseCase(this._repository);

  final ChatRepository _repository;

  Either<Failure, Unit> call(String sessionId) =>
      _repository.startReceivingMessages(sessionId: sessionId);
}
