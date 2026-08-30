import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_local_data_source.dart';
import '../models/chat_message_model.dart';

/// Passacarte verso il datasource locale, traducendo le eccezioni (o gli
/// errori della connessione condivisa) in `Failure`.
class ChatRepositoryImpl implements ChatRepository {
  const ChatRepositoryImpl(this._localDataSource);

  final ChatLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  }) async {
    try {
      return Right(
        await _localDataSource.getOrCreateConversation(
          otherPersonId: otherPersonId,
          otherSelfiePath: otherSelfiePath,
        ),
      );
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(
    String conversationId,
  ) async {
    try {
      return Right(await _localDataSource.getMessages(conversationId));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ChatMessage>> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  }) async {
    try {
      return Right(
        await _localDataSource.appendMessage(
          conversationId: conversationId,
          otherPersonId: otherPersonId,
          text: text,
        ),
      );
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Stream<Either<Failure, ChatMessage>> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) {
    return _localDataSource
        .watchIncomingMessages(sessionId: sessionId, otherPersonId: otherPersonId)
        .transform(
          StreamTransformer<ChatMessageModel, Either<Failure, ChatMessage>>.fromHandlers(
            handleData: (message, sink) => sink.add(Right(message)),
            handleError: (error, stackTrace, sink) =>
                sink.add(Left(UnexpectedFailure(error.toString()))),
          ),
        );
  }
}
