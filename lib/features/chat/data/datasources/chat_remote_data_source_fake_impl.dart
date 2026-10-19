import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_legacy_storage.dart';
import 'chat_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete): cronologia solo in memoria,
/// come quella reale, ma con un autoreply finto dopo ogni messaggio
/// mandato, per sentire la chat viva senza un vero interlocutore
/// dall'altra parte.
class ChatRemoteDataSourceFakeImpl implements ChatRemoteDataSource {
  ChatRemoteDataSourceFakeImpl() {
    unawaited(purgeLegacyChatStorage());
  }

  static const List<String> _fakeReplies = [
    'Ciao! Dove sei esattamente?',
    "Sono vicino all'entrata, tu?",
    'Perfetto, arrivo tra un minuto!',
  ];

  static const Duration _replyDelay = Duration(seconds: 3);

  final Random _random = Random();
  int _counter = 0;
  final Map<String, ConversationModel> _conversations = {};
  final Map<String, List<ChatMessageModel>> _messages = {};
  final Map<String, StreamController<ChatMessageModel>> _incomingControllers =
      {};

  @override
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  }) async {
    return _conversations.putIfAbsent(
      otherPersonId,
      () => ConversationModel(
        id: 'conv-$otherPersonId',
        otherPersonId: otherPersonId,
        otherSelfieBytes: otherSelfieBytes,
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
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
      isMine: true,
      text: text,
      sentAt: DateTime.now(),
    );
    _storeMessage(conversationId, message);
    _scheduleFakeReply(conversationId, otherPersonId);
    return message;
  }

  /// Nessuna connessione da ascoltare: le risposte finte nascono da
  /// [appendMessage].
  @override
  void startReceiving(String sessionId) {}

  @override
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) {
    return _incomingControllers
        .putIfAbsent(
          otherPersonId,
          StreamController<ChatMessageModel>.broadcast,
        )
        .stream;
  }

  void _scheduleFakeReply(String conversationId, String otherPersonId) {
    Timer(_replyDelay, () {
      // Il match potrebbe essere finito nel frattempo: niente risposta a
      // una conversazione che non esiste più.
      if (!_conversations.containsKey(otherPersonId)) return;
      final reply = ChatMessageModel(
        id: 'msg-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
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
    _messages.remove('conv-$otherPersonId')?.clear();
    _conversations.remove(otherPersonId);
    unawaited(_incomingControllers.remove(otherPersonId)?.close());
  }

  @override
  Stream<String> watchUndeliveredMessageIds({required String sessionId}) =>
      const Stream.empty();

  @override
  Future<void> reset() async {
    for (final list in _messages.values) {
      list.clear();
    }
    _messages.clear();
    _conversations.clear();
    for (final controller in _incomingControllers.values) {
      unawaited(controller.close());
    }
    _incomingControllers.clear();
  }

  void _storeMessage(String conversationId, ChatMessageModel message) {
    _messages.putIfAbsent(conversationId, () => []).add(message);
  }
}
