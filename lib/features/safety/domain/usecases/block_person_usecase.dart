import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../repositories/safety_repository.dart';

/// Azione: blocca una persona di questa sessione (da "Vicinanze", da una
/// richiesta o dal match). L'effetto lo applica **il server**, subito e nei
/// due sensi: non vi vedete più, le richieste tra voi sono cancellate, il
/// match (se c'è) si chiude e la chat non passa più. L'altra persona non
/// viene avvisata: vede ciò che vedrebbe se tu fossi uscito.
///
/// Dura per il resto della sessione (anche attraverso le riconnessioni);
/// dopo End non può sopravvivere, perché non esistono id permanenti.
///
/// `Right` = partito (e la persona è già nascosta qui); `Left(
/// ConnectionFailure)` = non è partito, si può riprovare.
class BlockPersonUseCase {
  const BlockPersonUseCase(this._repository);

  final SafetyRepository _repository;

  Either<Failure, Unit> call(String personId) {
    if (personId.isEmpty) {
      return const Left(ValidationFailure('Unknown person'));
    }
    return _repository.blockPerson(personId);
  }
}
