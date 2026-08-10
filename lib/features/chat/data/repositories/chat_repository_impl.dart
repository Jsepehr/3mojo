import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_local_data_source.dart';

/// Passacarte verso il datasource locale, traducendo le eccezioni in `Failure`.
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
    required String text,
  }) async {
    try {
      return Right(
        await _localDataSource.appendMessage(
          conversationId: conversationId,
          text: text,
        ),
      );
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
