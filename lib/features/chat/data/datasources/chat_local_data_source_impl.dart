import 'dart:async';

import '/core/network/realtime_connection.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_legacy_storage.dart';
import 'chat_local_data_source.dart';

/// Implementazione **reale**: cronologia tenuta **solo in memoria** (né il
/// server né il telefono la conservano: chiusa l'app o finito il match, non
/// ne resta traccia), e consegna vera tramite la connessione WebSocket
/// condivisa con `nearby`/`encounters` (`RealtimeConnection`) — nessun
/// autoreply finto.
class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  ChatLocalDataSourceImpl() {
    unawaited(purgeLegacyChatStorage());
  }

  final Map<String, ConversationModel> _conversations = {};
  final Map<String, List<ChatMessageModel>> _messages = {};

  @override
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    return _conversations.putIfAbsent(
      otherPersonId,
      () => ConversationModel(
        id: 'conv-$otherPersonId',
        otherPersonId: otherPersonId,
        otherSelfiePath: otherSelfiePath,
      ),
    );
  }

  @override
  Future<List<ChatMessageModel>> getMessages(String conversationId) async =>
      List.of(_messages[conversationId] ?? const []);

  @override
  Future<ChatMessageModel> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  }) async {
    final message = ChatMessageModel(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      isMine: true,
      text: text,
      sentAt: DateTime.now(),
    );
    _storeMessage(conversationId, message);

    RealtimeConnection.instance.send({
      'type': 'chatMessage',
      'toSessionId': otherPersonId,
      'text': message.text,
      'sentAt': message.sentAt.toIso8601String(),
    });

    return message;
  }

  @override
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) {
    final messages = RealtimeConnection.instance.connect(sessionId);

    return messages
        .where(
          (decoded) =>
              decoded['type'] == 'chatMessage' &&
              decoded['fromSessionId'] == otherPersonId,
        )
        .map((decoded) {
          final message = ChatMessageModel(
            id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
            isMine: false,
            text: decoded['text'] as String,
            sentAt: DateTime.parse(decoded['sentAt'] as String),
          );
          _storeMessage('conv-$otherPersonId', message);
          return message;
        });
  }

  @override
  Future<void> deleteConversation(String otherPersonId) async {
    _messages.remove('conv-$otherPersonId');
    _conversations.remove(otherPersonId);
  }

  void _storeMessage(String conversationId, ChatMessageModel message) {
    _messages.putIfAbsent(conversationId, () => []).add(message);
  }
}
