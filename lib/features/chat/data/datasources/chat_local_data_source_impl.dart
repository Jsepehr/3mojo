import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '/core/network/realtime_connection.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_local_data_source.dart';

/// Implementazione **reale**: cronologia salvata come JSON in
/// `shared_preferences` (il server fa solo da postino, non la conserva), e
/// consegna vera tramite la connessione WebSocket condivisa con `nearby`/
/// `encounters` (`RealtimeConnection`) — nessun autoreply finto.
class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  static const String _conversationsKey = 'chat_conversations';
  static const String _messagesKeyPrefix = 'chat_messages_';

  @override
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    final conversations = await _loadConversations();
    final existingIndex = conversations.indexWhere(
      (c) => c.otherPersonId == otherPersonId,
    );
    if (existingIndex != -1) {
      return conversations[existingIndex];
    }

    final created = ConversationModel(
      id: 'conv-$otherPersonId',
      otherPersonId: otherPersonId,
      otherSelfiePath: otherSelfiePath,
    );
    conversations.add(created);
    await _saveConversations(conversations);
    return created;
  }

  @override
  Future<List<ChatMessageModel>> getMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_messagesKeyPrefix$conversationId');
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

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
    await _storeMessage(conversationId, message);

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
        .asyncMap((decoded) async {
          final message = ChatMessageModel(
            id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
            isMine: false,
            text: decoded['text'] as String,
            sentAt: DateTime.parse(decoded['sentAt'] as String),
          );
          await _storeMessage('conv-$otherPersonId', message);
          return message;
        });
  }

  @override
  Future<void> deleteConversation(String otherPersonId) async {
    final conversationId = 'conv-$otherPersonId';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_messagesKeyPrefix$conversationId');

    final conversations = await _loadConversations();
    conversations.removeWhere((c) => c.otherPersonId == otherPersonId);
    await _saveConversations(conversations);
  }

  Future<void> _storeMessage(
    String conversationId,
    ChatMessageModel message,
  ) async {
    final messages = await getMessages(conversationId);
    messages.add(message);
    await _saveMessages(conversationId, messages);
  }

  Future<List<ConversationModel>> _loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveConversations(List<ConversationModel> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _conversationsKey,
      jsonEncode(conversations.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _saveMessages(
    String conversationId,
    List<ChatMessageModel> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_messagesKeyPrefix$conversationId',
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }
}
