import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

/// Azione: leggi i messaggi di una conversazione.
class GetMessagesUseCase implements UseCase<List<ChatMessage>, String> {
  const GetMessagesUseCase(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, List<ChatMessage>>> call(String conversationId) =>
      _repository.getMessages(conversationId);
}
