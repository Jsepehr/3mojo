import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/chat/domain/usecases/delete_conversation_usecase.dart';

/// Azione: un match è finito **non** per mano tua (l'altra persona l'ha
/// chiuso o è andata offline, oppure il server ha dimenticato la sessione
/// durante una caduta): la chat con quella persona non sopravvive, come
/// quando lo chiudi tu (`EndMatchUseCase`).
class ForgetEndedMatchUseCase {
  const ForgetEndedMatchUseCase(this._deleteConversationUseCase);

  final DeleteConversationUseCase _deleteConversationUseCase;

  Future<Either<Failure, Unit>> call(String otherPersonId) async {
    final result = await _deleteConversationUseCase(otherPersonId);
    return result.map((_) => unit);
  }
}
