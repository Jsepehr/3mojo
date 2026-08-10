import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/conversation.dart';
import '../repositories/chat_repository.dart';

class GetOrCreateConversationParams extends Equatable {
  const GetOrCreateConversationParams({
    required this.otherPersonId,
    required this.otherSelfiePath,
  });

  final String otherPersonId;
  final String otherSelfiePath;

  @override
  List<Object?> get props => [otherPersonId, otherSelfiePath];
}

class GetOrCreateConversationUseCase
    implements UseCase<Conversation, GetOrCreateConversationParams> {
  const GetOrCreateConversationUseCase(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, Conversation>> call(
    GetOrCreateConversationParams params,
  ) => _repository.getOrCreateConversation(
    otherPersonId: params.otherPersonId,
    otherSelfiePath: params.otherSelfiePath,
  );
}
