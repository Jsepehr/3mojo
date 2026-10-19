import 'dart:async';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/exceptions.dart';
import '/core/errors/failures.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../models/chat_message_model.dart';

/// Passacarte verso il datasource, traducendo gli errori della connessione
/// (`ServerException`) in `ConnectionFailure` e ogni altra eccezione in
/// `UnexpectedFailure`.
class ChatRepositoryImpl implements ChatRepository {
  const ChatRepositoryImpl(this._remoteDataSource);

  final ChatRemoteDataSource _remoteDataSource;

  static Failure _failureFor(Object error) => error is ServerException
      ? ConnectionFailure(error.message)
      : UnexpectedFailure(error.toString());

  @override
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  }) async {
    try {
      return Right(
        await _remoteDataSource.getOrCreateConversation(
          otherPersonId: otherPersonId,
          otherSelfieBytes: otherSelfieBytes,
        ),
      );
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(
    String conversationId,
  ) async {
    try {
      return Right(await _remoteDataSource.getMessages(conversationId));
    } catch (e) {
      return Left(_failureFor(e));
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
        await _remoteDataSource.appendMessage(
          conversationId: conversationId,
          otherPersonId: otherPersonId,
          text: text,
        ),
      );
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  @override
  Future<Either<Failure, void>> deleteConversation(String otherPersonId) async {
    try {
      await _remoteDataSource.deleteConversation(otherPersonId);
      return const Right(null);
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  @override
  Stream<String> watchUndeliveredMessageIds({required String sessionId}) =>
      _remoteDataSource
          .watchUndeliveredMessageIds(sessionId: sessionId)
          .handleError((Object _) {});

  @override
  Future<Either<Failure, Unit>> clearSessionState() async {
    try {
      await _remoteDataSource.reset();
      return const Right(unit);
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  @override
  Either<Failure, Unit> startReceivingMessages({required String sessionId}) {
    try {
      _remoteDataSource.startReceiving(sessionId);
      return const Right(unit);
    } catch (e) {
      return Left(_failureFor(e));
    }
  }

  @override
  Stream<Either<Failure, ChatMessage>> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  }) {
    return _remoteDataSource
        .watchIncomingMessages(
          sessionId: sessionId,
          otherPersonId: otherPersonId,
        )
        .transform(
          StreamTransformer<
            ChatMessageModel,
            Either<Failure, ChatMessage>
          >.fromHandlers(
            handleData: (message, sink) => sink.add(Right(message)),
            handleError: (error, stackTrace, sink) =>
                sink.add(Left(_failureFor(error))),
          ),
        );
  }
}
