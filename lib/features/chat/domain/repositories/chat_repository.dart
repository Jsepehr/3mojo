import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/chat_message.dart';
import '../entities/conversation.dart';

abstract class ChatRepository {
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<Either<Failure, List<ChatMessage>>> getMessages(String conversationId);

  Future<Either<Failure, ChatMessage>> appendMessage({
    required String conversationId,
    required String text,
  });
}
