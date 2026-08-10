import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_local_data_source.dart';

class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  static const String _conversationsKey = 'chat_conversations';
  static const String _messagesKeyPrefix = 'chat_messages_';

  static const List<String> _fakeReplies = [
    "Ciao! Dove sei esattamente?",
    "Sono vicino all'entrata, tu?",
    'Perfetto, arrivo tra un minuto!',
  ];

  final Random _random = Random();

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
    required String text,
  }) async {
    final messages = await getMessages(conversationId);
    final message = ChatMessageModel(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      isMine: true,
      text: text,
      sentAt: DateTime.now(),
    );
    messages.add(message);
    await _saveMessages(conversationId, messages);

    _scheduleFakeReply(conversationId);

    return message;
  }

  void _scheduleFakeReply(String conversationId) {
    Future<void>.delayed(const Duration(seconds: 3), () async {
      final messages = await getMessages(conversationId);
      messages.add(
        ChatMessageModel(
          id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
          isMine: false,
          text: _fakeReplies[_random.nextInt(_fakeReplies.length)],
          sentAt: DateTime.now(),
        ),
      );
      await _saveMessages(conversationId, messages);
    });
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
