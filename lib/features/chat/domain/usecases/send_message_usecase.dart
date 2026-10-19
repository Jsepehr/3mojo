import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class SendMessageParams extends Equatable {
  const SendMessageParams({
    required this.conversationId,
    required this.otherPersonId,
    required this.text,
  });

  final String conversationId;
  final String otherPersonId;
  final String text;

  @override
  List<Object?> get props => [conversationId, otherPersonId, text];
}

/// Azione: manda un messaggio. Regole prima di mandarlo: non vuoto e non
/// più lungo di [maxTextLength] (`MessageTooLongFailure`) — lo stesso
/// limite del server, che altrimenti lo rifiuterebbe (`invalidText`) e un
/// "Riprova" fallirebbe per sempre.
class SendMessageUseCase implements UseCase<ChatMessage, SendMessageParams> {
  const SendMessageUseCase(this._repository);

  /// Lunghezza massima del testo (dopo il `trim`), in unità UTF-16
  /// (`String.length`, come conta il server). **Allineata** con
  /// `RealtimeMessageHandler.maxChatTextLength` in `server/`: cambiarle
  /// insieme.
  static const maxTextLength = 1000;

  final ChatRepository _repository;

  @override
  Future<Either<Failure, ChatMessage>> call(SendMessageParams params) {
    final text = params.text.trim();
    if (text.isEmpty) {
      return Future.value(
        const Left(ValidationFailure('Il messaggio non può essere vuoto')),
      );
    }
    if (text.length > maxTextLength) {
      return Future.value(const Left(MessageTooLongFailure(maxTextLength)));
    }

    return _repository.appendMessage(
      conversationId: params.conversationId,
      otherPersonId: params.otherPersonId,
      text: text,
    );
  }
}
