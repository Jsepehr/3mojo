import 'dart:async';
import 'dart:typed_data';

import '/core/errors/exceptions.dart';
import '/core/network/realtime_connection.dart';
import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';
import 'chat_legacy_storage.dart';
import 'chat_remote_data_source.dart';

/// Implementazione **reale**: cronologia tenuta **solo in memoria** (né il
/// server né il telefono la conservano: chiusa l'app, finita la sessione o
/// il match, non ne resta traccia), e consegna vera tramite la connessione
/// WebSocket condivisa con `nearby`/`encounters` (`RealtimeConnection`) —
/// nessun autoreply finto.
///
/// **Un solo ascolto** della connessione per sessione, aperto all'inizio
/// della sessione ([startReceiving], da `ProChat`): riceve ogni
/// `chatMessage`, lo aggiunge alla cronologia una sola volta e lo inoltra a
/// chi ascolta quella conversazione. Così un messaggio arrivato prima che
/// la pagina del match si apra non va perso: è già nella cronologia quando
/// la pagina la legge. Prima ogni ascoltatore salvava di
/// nuovo lo stesso messaggio (doppioni con due ascoltatori, nessun salvataggio
/// con zero).
class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  ChatRemoteDataSourceImpl({RealtimeConnection? connection})
    : _connection = connection ?? RealtimeConnection.instance {
    unawaited(purgeLegacyChatStorage());
  }

  final RealtimeConnection _connection;
  final Map<String, ConversationModel> _conversations = {};
  final Map<String, List<ChatMessageModel>> _messages = {};
  final Map<String, StreamController<ChatMessageModel>> _incoming = {};
  final StreamController<String> _undelivered = StreamController.broadcast();

  /// Chi ha avuto un match finito in questa sessione: i suoi messaggi
  /// tardivi non ricreano una cronologia appena cancellata.
  final Set<String> _endedPersonIds = {};

  String? _sessionId;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  int _messageCounter = 0;

  static String _conversationIdFor(String otherPersonId) =>
      'conv-$otherPersonId';

  String _newMessageId() =>
      'msg-${DateTime.now().microsecondsSinceEpoch}-${_messageCounter++}';

  @override
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  }) async {
    _endedPersonIds.remove(otherPersonId);
    return _conversations.putIfAbsent(
      otherPersonId,
      () => ConversationModel(
        id: _conversationIdFor(otherPersonId),
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
      id: _newMessageId(),
      isMine: true,
      text: text,
      sentAt: DateTime.now(),
    );

    final sent = _connection.send({
      'type': 'chatMessage',
      'toPersonId': otherPersonId,
      'text': message.text,
      'clientMessageId': message.id,
    });
    if (!sent) {
      throw const ServerException('Non connesso al server: non inviato');
    }

    _messages.putIfAbsent(conversationId, () => []).add(message);
    return message;
  }

  @override
  void startReceiving(String sessionId) => _listenTo(sessionId);

  @override
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) {
    _listenTo(sessionId);
    return _controllerFor(otherPersonId).stream;
  }

  StreamController<ChatMessageModel> _controllerFor(String otherPersonId) {
    final existing = _incoming[otherPersonId];
    if (existing != null && !existing.isClosed) return existing;
    return _incoming[otherPersonId] = StreamController.broadcast();
  }

  void _listenTo(String sessionId) {
    if (_sessionId == sessionId && _subscription != null) return;

    _forgetEverything();
    _sessionId = sessionId;
    _subscription = _connection
        .connect(sessionId)
        .listen(
          _onMessage,
          // Connessione caduta: lo dice a chi ascolta (→ ConnectionFailure),
          // la riconnessione è automatica.
          onError: (Object error, StackTrace stackTrace) {
            for (final controller in _incoming.values) {
              if (!controller.isClosed) controller.addError(error, stackTrace);
            }
          },
          // Fine della sessione (End o un'altra sessione): non ne resta
          // nulla.
          onDone: () {
            if (_sessionId == sessionId) _forgetEverything();
          },
        );
  }

  @override
  Stream<String> watchUndeliveredMessageIds({required String sessionId}) {
    _listenTo(sessionId);
    return _undelivered.stream;
  }

  @override
  Future<void> reset() async => _forgetEverything();

  void _onMessage(Map<String, dynamic> decoded) {
    if (decoded['type'] == 'rejected' && decoded['action'] == 'chatMessage') {
      final clientMessageId = decoded['clientMessageId'];
      if (clientMessageId is String) _undelivered.add(clientMessageId);
      return;
    }
    if (decoded['type'] != 'chatMessage') return;
    final from = decoded['fromPersonId'];
    final text = decoded['text'];
    if (from is! String || text is! String) return;
    if (_endedPersonIds.contains(from)) return;

    final message = ChatMessageModel(
      id: _newMessageId(),
      isMine: false,
      text: text,
      sentAt:
          DateTime.tryParse(decoded['sentAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
    _messages.putIfAbsent(_conversationIdFor(from), () => []).add(message);
    final controller = _incoming[from];
    if (controller != null && !controller.isClosed) controller.add(message);
  }

  @override
  Future<void> deleteConversation(String otherPersonId) async {
    _messages.remove(_conversationIdFor(otherPersonId))?.clear();
    _conversations.remove(otherPersonId);
    _endedPersonIds.add(otherPersonId);
  }

  void _forgetEverything() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _sessionId = null;
    for (final list in _messages.values) {
      list.clear();
    }
    _messages.clear();
    _conversations.clear();
    _endedPersonIds.clear();
    for (final controller in _incoming.values) {
      unawaited(controller.close());
    }
    _incoming.clear();
  }
}
