import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/usecases/get_messages_usecase.dart';
import '../../domain/usecases/get_or_create_conversation_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';

/// Stato della chat aperta: messaggi, se sta caricando, polling ogni 2s
/// per vedere l'autoreply finto senza dover ricaricare manualmente.
class ProChat extends ChangeNotifier {
  ProChat({
    required GetOrCreateConversationUseCase getOrCreateConversationUseCase,
    required GetMessagesUseCase getMessagesUseCase,
    required SendMessageUseCase sendMessageUseCase,
  }) : _getOrCreateConversationUseCase = getOrCreateConversationUseCase,
       _getMessagesUseCase = getMessagesUseCase,
       _sendMessageUseCase = sendMessageUseCase;

  final GetOrCreateConversationUseCase _getOrCreateConversationUseCase;
  final GetMessagesUseCase _getMessagesUseCase;
  final SendMessageUseCase _sendMessageUseCase;

  Timer? _pollTimer;
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
    });

    _isLoading = false;
    notifyListeners();

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollMessages(),
    );
  }

  Future<void> sendMessage(String text) async {
    final conversation = _conversation;
    if (conversation == null) return;

    final result = await _sendMessageUseCase(
      SendMessageParams(conversationId: conversation.id, text: text),
    );
    await result.match((failure) async => _errorMessage = failure.message, (
      _,
    ) async {
      _errorMessage = null;
      await _loadMessages();
    });
    notifyListeners();
  }

  Future<void> _pollMessages() async {
    final before = _messages.length;
    await _loadMessages();
    if (_messages.length != before) notifyListeners();
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
    _pollTimer?.cancel();
    super.dispose();
  }
}
