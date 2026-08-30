import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/usecases/get_messages_usecase.dart';
import '../../domain/usecases/get_or_create_conversation_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';
import '../../domain/usecases/watch_incoming_chat_messages_usecase.dart';

/// Stato della chat aperta: messaggi, se sta caricando. I messaggi in
/// arrivo sono spinti dalla connessione condivisa (`WatchIncomingChatMessagesUseCase`),
/// niente più polling né autoreply finto — come `ProNearby`/`ProEncounters`,
/// se lo stream finisce ci si riabbona da soli dopo una breve pausa.
class ProChat extends ChangeNotifier {
  ProChat({
    required GetOrCreateConversationUseCase getOrCreateConversationUseCase,
    required GetMessagesUseCase getMessagesUseCase,
    required SendMessageUseCase sendMessageUseCase,
    required WatchIncomingChatMessagesUseCase watchIncomingChatMessagesUseCase,
  }) : _getOrCreateConversationUseCase = getOrCreateConversationUseCase,
       _getMessagesUseCase = getMessagesUseCase,
       _sendMessageUseCase = sendMessageUseCase,
       _watchIncomingChatMessagesUseCase = watchIncomingChatMessagesUseCase;

  static const Duration _resubscribeDelay = Duration(seconds: 3);

  final GetOrCreateConversationUseCase _getOrCreateConversationUseCase;
  final GetMessagesUseCase _getMessagesUseCase;
  final SendMessageUseCase _sendMessageUseCase;
  final WatchIncomingChatMessagesUseCase _watchIncomingChatMessagesUseCase;

  StreamSubscription<void>? _subscription;
  Timer? _resubscribeTimer;
  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;

  Conversation? get conversation => _conversation;
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> open({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    _resubscribeTimer?.cancel();
    await _subscription?.cancel();

    _isLoading = true;
    // Deferred: open() is called from UiActiveMatch.initState(), which runs
    // while _MatchGate's own build is still in progress — notifying
    // synchronously here would try to rebuild during that build.
    scheduleMicrotask(notifyListeners);

    final result = await _getOrCreateConversationUseCase(
      GetOrCreateConversationParams(
        otherPersonId: otherPersonId,
        otherSelfiePath: otherSelfiePath,
      ),
    );
    await result.match((failure) async => _errorMessage = failure.message, (
      conversation,
    ) async {
      _conversation = conversation;
      await _loadMessages();
      _subscribeToIncoming(otherPersonId);
    });

    _isLoading = false;
    notifyListeners();
  }

  void _subscribeToIncoming(String otherPersonId) {
    _subscription = _watchIncomingChatMessagesUseCase(otherPersonId).listen(
      (result) {
        result.match((failure) => _errorMessage = failure.message, (message) {
          _messages = [..._messages, message];
          _errorMessage = null;
        });
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        notifyListeners();
      },
      onDone: () => _scheduleResubscribe(otherPersonId),
    );
  }

  void _scheduleResubscribe(String otherPersonId) {
    _resubscribeTimer = Timer(
      _resubscribeDelay,
      () => _subscribeToIncoming(otherPersonId),
    );
  }

  Future<void> sendMessage(String text) async {
    final conversation = _conversation;
    if (conversation == null) return;

    final result = await _sendMessageUseCase(
      SendMessageParams(
        conversationId: conversation.id,
        otherPersonId: conversation.otherPersonId,
        text: text,
      ),
    );
    result.match((failure) => _errorMessage = failure.message, (message) {
      _messages = [..._messages, message];
      _errorMessage = null;
    });
    notifyListeners();
  }

  Future<void> _loadMessages() async {
    final conversation = _conversation;
    if (conversation == null) return;

    final result = await _getMessagesUseCase(conversation.id);
    result.match(
      (failure) => _errorMessage = failure.message,
      (messages) => _messages = messages,
    );
  }

  @override
  void dispose() {
    _resubscribeTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
