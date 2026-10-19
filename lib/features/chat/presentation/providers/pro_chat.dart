import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/usecases/get_messages_usecase.dart';
import '../../domain/usecases/get_or_create_conversation_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';
import '../../domain/usecases/start_receiving_chat_messages_usecase.dart';
import '../../domain/usecases/watch_incoming_chat_messages_usecase.dart';
import '../../domain/usecases/watch_undelivered_chat_messages_usecase.dart';

/// Stato della chat del match aperto: messaggi, se sta caricando. I
/// messaggi in arrivo sono spinti dalla connessione condivisa
/// (`WatchIncomingChatMessagesUseCase`); una caduta di rete non chiude lo
/// stream (riconnessione automatica, vedi `CmpConnectionBanner`), quindi
/// niente più timer di riabbonamento.
///
/// Un messaggio che non parte (offline) o che il server non consegna
/// (`WatchUndeliveredChatMessagesUseCase`) resta nella chat marcato come
/// **non inviato** ([isUnsent]) — mai finto partito — e si può
/// [resend]are.
///
/// Vive per tutta l'app ma lavora solo per il match aperto: [close] (chiamato
/// da `CmpMatchGate` quando la pagina del match si chiude, per qualsiasi
/// motivo, e da sé a fine sessione) ferma gli ascolti e svuota i messaggi.
/// A ogni Start fa partire la ricezione dei messaggi
/// (`StartReceivingChatMessagesUseCase`), così quelli arrivati prima che la
/// pagina del match si apra sono già in cronologia quando la si apre.
///
/// Un messaggio che non rispetta le regole (vuoto, troppo lungo:
/// `MessageTooLongFailure`) non entra nella chat né come "non inviato":
/// [sendMessage] ritorna il `Failure` e la UI lo racconta.
class ProChat extends ChangeNotifier {
  ProChat({
    required WatchSessionUseCase watchSessionUseCase,
    required GetOrCreateConversationUseCase getOrCreateConversationUseCase,
    required GetMessagesUseCase getMessagesUseCase,
    required SendMessageUseCase sendMessageUseCase,
    required StartReceivingChatMessagesUseCase
    startReceivingChatMessagesUseCase,
    required WatchIncomingChatMessagesUseCase watchIncomingChatMessagesUseCase,
    required WatchUndeliveredChatMessagesUseCase
    watchUndeliveredChatMessagesUseCase,
  }) : _getOrCreateConversationUseCase = getOrCreateConversationUseCase,
       _getMessagesUseCase = getMessagesUseCase,
       _sendMessageUseCase = sendMessageUseCase,
       _watchIncomingChatMessagesUseCase = watchIncomingChatMessagesUseCase,
       _watchUndeliveredChatMessagesUseCase =
           watchUndeliveredChatMessagesUseCase {
    _sessionSubscription = watchSessionUseCase().listen((session) {
      if (session == null) {
        close();
      } else {
        startReceivingChatMessagesUseCase(session.sessionId);
      }
    });
  }

  final GetOrCreateConversationUseCase _getOrCreateConversationUseCase;
  final GetMessagesUseCase _getMessagesUseCase;
  final SendMessageUseCase _sendMessageUseCase;
  final WatchIncomingChatMessagesUseCase _watchIncomingChatMessagesUseCase;
  final WatchUndeliveredChatMessagesUseCase
  _watchUndeliveredChatMessagesUseCase;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  StreamSubscription<void>? _incomingSubscription;
  StreamSubscription<void>? _undeliveredSubscription;

  /// Cresce a ogni [open]/[close]: un caricamento partito per una chat
  /// chiusa nel frattempo non deve riempire quella nuova.
  int _generation = 0;
  int _unsentCounter = 0;
  bool _disposed = false;

  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  final Set<String> _unsentIds = {};
  bool _isLoading = false;
  Failure? _failure;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;

  /// Perché la chat non si è potuta aprire, o `null`. La UI sceglie il
  /// testo, mai il `message` tecnico.
  Failure? get failure => _failure;

  /// Il messaggio non è partito o non è stato consegnato.
  bool isUnsent(ChatMessage message) => _unsentIds.contains(message.id);

  Future<void> open({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  }) async {
    _cancelSubscriptions();
    final generation = ++_generation;
    _conversation = null;
    _messages = [];
    _unsentIds.clear();
    _failure = null;
    _isLoading = true;
    // Rimandata: open() è chiamata da UiActiveMatch.initState(), durante
    // un build — notificare subito proverebbe a ricostruire durante quel
    // build.
    scheduleMicrotask(_notify);

    final result = await _getOrCreateConversationUseCase(
      GetOrCreateConversationParams(
        otherPersonId: otherPersonId,
        otherSelfieBytes: otherSelfieBytes,
      ),
    );
    if (generation != _generation) return;

    switch (result) {
      case Left(:final value):
        _failure = value;
      case Right(value: final conversation):
        _conversation = conversation;
        final messages = await _getMessagesUseCase(conversation.id);
        if (generation != _generation) return;
        messages.match(
          (failure) => _failure = failure,
          (list) => _messages = list,
        );
        _subscribe(otherPersonId);
    }

    _isLoading = false;
    _notify();
  }

  void _subscribe(String otherPersonId) {
    _incomingSubscription = _watchIncomingChatMessagesUseCase(otherPersonId)
        .listen((result) {
          // Gli errori (caduta di rete, fine sessione) non tolgono nulla dalla
          // chat: li raccontano l'indicatore di connessione e la fine del match.
          result.match((_) {}, (message) {
            _messages = [..._messages, message];
            _notify();
          });
        });
    _undeliveredSubscription = _watchUndeliveredChatMessagesUseCase().listen((
      messageId,
    ) {
      if (!_messages.any((message) => message.id == messageId)) return;
      _unsentIds.add(messageId);
      _notify();
    });
  }

  /// Manda [text]. Ritorna il `Failure` se il messaggio non rispetta le
  /// regole (`ValidationFailure`, es. `MessageTooLongFailure`): in quel caso
  /// non entra nella chat e la UI lo deve dire. Un messaggio valido che non
  /// parte (offline) resta invece nella chat come "non inviato" e ritorna
  /// `null`, come uno partito.
  Future<Failure?> sendMessage(String text) async {
    final conversation = _conversation;
    if (conversation == null || text.trim().isEmpty) return null;
    final generation = _generation;

    final result = await _sendMessageUseCase(
      SendMessageParams(
        conversationId: conversation.id,
        otherPersonId: conversation.otherPersonId,
        text: text,
      ),
    );
    if (generation != _generation) return null;
    if (result case Left(value: final ValidationFailure failure)) {
      return failure;
    }

    result.match((_) {
      final unsent = ChatMessage(
        id: 'unsent-${_unsentCounter++}',
        isMine: true,
        text: text.trim(),
        sentAt: DateTime.now(),
      );
      _messages = [..._messages, unsent];
      _unsentIds.add(unsent.id);
    }, (message) => _messages = [..._messages, message]);
    _notify();
    return null;
  }

  /// Riprova a mandare un messaggio non inviato: sparisce dalla chat e
  /// riparte come nuovo (se fallisce ancora, torna "non inviato").
  Future<void> resend(ChatMessage message) async {
    if (!_unsentIds.remove(message.id)) return;
    _messages = [
      for (final m in _messages)
        if (m.id != message.id) m,
    ];
    _notify();
    await sendMessage(message.text);
  }

  /// Chiude la chat aperta: ferma gli ascolti e svuota i messaggi (restano
  /// solo dove li tiene il datasource, finché il match non finisce).
  void close() {
    _generation++;
    _cancelSubscriptions();
    final hadState =
        _conversation != null || _messages.isNotEmpty || _isLoading;
    _conversation = null;
    _messages = [];
    _unsentIds.clear();
    _failure = null;
    _isLoading = false;
    // Rimandata: close() può arrivare mentre la pagina del match viene
    // smontata.
    if (hadState) scheduleMicrotask(_notify);
  }

  void _cancelSubscriptions() {
    _incomingSubscription?.cancel();
    _incomingSubscription = null;
    _undeliveredSubscription?.cancel();
    _undeliveredSubscription = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSubscription.cancel();
    _cancelSubscriptions();
    super.dispose();
  }
}
