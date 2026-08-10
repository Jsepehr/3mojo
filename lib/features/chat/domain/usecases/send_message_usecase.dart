import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class SendMessageParams extends Equatable {
  const SendMessageParams({required this.conversationId, required this.text});

  final String conversationId;
  final String text;

  @override
  List<Object?> get props => [conversationId, text];
}

/// Azione: manda un messaggio. Valida che non sia vuoto prima di scriverlo.
class SendMessageUseCase implements UseCase<ChatMessage, SendMessageParams> {
  const SendMessageUseCase(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, ChatMessage>> call(SendMessageParams params) {
    final text = params.text.trim();
    if (text.isEmpty) {
      return Future.value(
        const Left(ValidationFailure('Il messaggio non può essere vuoto')),
      );
    }

    return _repository.appendMessage(
      conversationId: params.conversationId,
      text: text,
    );
  }
}
