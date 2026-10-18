import 'dart:async';
import 'dart:math';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_legacy_storage.dart';
import 'chat_local_data_source.dart';

/// Implementazione **finta** (nessuna rete): cronologia solo in memoria,
/// come quella reale, ma con un autoreply finto dopo ogni messaggio
/// mandato, per sentire la chat viva senza un vero interlocutore
/// dall'altra parte.
class ChatLocalDataSourceFakeImpl implements ChatLocalDataSource {
  ChatLocalDataSourceFakeImpl() {
    unawaited(purgeLegacyChatStorage());
  }

  static const List<String> _fakeReplies = [
    'Ciao! Dove sei esattamente?',
    "Sono vicino all'entrata, tu?",
    'Perfetto, arrivo tra un minuto!',
  ];

  static const Duration _replyDelay = Duration(seconds: 3);

  final Random _random = Random();
  final Map<String, ConversationModel> _conversations = {};
  final Map<String, List<ChatMessageModel>> _messages = {};
  final Map<String, StreamController<ChatMessageModel>> _incomingControllers =
      {};

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
    Timer(_replyDelay, () {
      // Il match potrebbe essere finito nel frattempo: niente risposta a
      // una conversazione che non esiste più.
      if (!_conversations.containsKey(otherPersonId)) return;
      final reply = ChatMessageModel(
        id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
        isMine: false,
        text: _fakeReplies[_random.nextInt(_fakeReplies.length)],
        sentAt: DateTime.now(),
      );
      _storeMessage(conversationId, reply);
      _incomingControllers[otherPersonId]?.add(reply);
    });
  }

  @override
  Future<void> deleteConversation(String otherPersonId) async {
    _messages.remove('conv-$otherPersonId');
    _conversations.remove(otherPersonId);
    unawaited(_incomingControllers.remove(otherPersonId)?.close());
  }

  void _storeMessage(String conversationId, ChatMessageModel message) {
    _messages.putIfAbsent(conversationId, () => []).add(message);
  }
}
