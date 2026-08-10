import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';

abstract class ChatLocalDataSource {
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<List<ChatMessageModel>> getMessages(String conversationId);

  Future<ChatMessageModel> appendMessage({
    required String conversationId,
    required String text,
  });
}
