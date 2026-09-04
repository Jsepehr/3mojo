import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/chat_repository.dart';

/// Azione: cancella la conversazione con `otherPersonId` e la sua
/// cronologia — chiamata quando un match finisce, così la chat non
/// sopravvive alla fine dell'incontro.
class DeleteConversationUseCase implements UseCase<void, String> {
  const DeleteConversationUseCase(this._repository);

  final ChatRepository _repository;

  @override
  Future<Either<Failure, void>> call(String otherPersonId) =>
      _repository.deleteConversation(otherPersonId);
}
