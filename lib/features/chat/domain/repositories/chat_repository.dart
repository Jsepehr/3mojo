import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/chat_message.dart';
import '../entities/conversation.dart';

/// Contratto per aprire una conversazione e scambiare messaggi in tempo
/// reale con la controparte.
abstract class ChatRepository {
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<Either<Failure, List<ChatMessage>>> getMessages(String conversationId);

  Future<Either<Failure, ChatMessage>> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  });

  Stream<Either<Failure, ChatMessage>> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  });

  Future<Either<Failure, void>> deleteConversation(String otherPersonId);
}
