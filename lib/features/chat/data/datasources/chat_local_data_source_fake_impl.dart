import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_local_data_source.dart';

/// Implementazione **finta** (nessuna rete): cronologia salvata come JSON in
/// `shared_preferences` (chiavi separate da quelle reali, così passare da
/// una modalità all'altra non mischia le conversazioni), ma con un
/// autoreply finto dopo ogni messaggio mandato, per sentire la chat viva
/// senza un vero interlocutore dall'altra parte.
class ChatLocalDataSourceFakeImpl implements ChatLocalDataSource {
  static const String _conversationsKey = 'fake_chat_conversations';
  static const String _messagesKeyPrefix = 'fake_chat_messages_';

  static const List<String> _fakeReplies = [
    'Ciao! Dove sei esattamente?',
    "Sono vicino all'entrata, tu?",
    'Perfetto, arrivo tra un minuto!',
  ];

  static const Duration _replyDelay = Duration(seconds: 3);

  final Random _random = Random();
  final Map<String, StreamController<ChatMessageModel>> _incomingControllers =
      {};

  @override
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    final conversations = await _loadConversations();
    final existingIndex = conversations.indexWhere(
      (c) => c.otherPersonId == otherPersonId,
    );
    if (existingIndex != -1) return conversations[existingIndex];

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
    _scheduleFakeReply(conversationId, otherPersonId);
    return message;
  }

  @override
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) {
    return _incomingControllers
        .putIfAbsent(otherPersonId, StreamController<ChatMessageModel>.broadcast)
        .stream;
  }

  void _scheduleFakeReply(String conversationId, String otherPersonId) {
    Timer(_replyDelay, () async {
      final reply = ChatMessageModel(
        id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
        isMine: false,
        text: _fakeReplies[_random.nextInt(_fakeReplies.length)],
        sentAt: DateTime.now(),
      );
      await _storeMessage(conversationId, reply);
      _incomingControllers[otherPersonId]?.add(reply);
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

    unawaited(_incomingControllers.remove(otherPersonId)?.close());
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
