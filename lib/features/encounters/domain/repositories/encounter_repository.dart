import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/encounter_request.dart';

/// Contratto per inviare/ricevere/rispondere a richieste d'interesse.
/// L'esclusività ("un solo match attivo alla volta") è applicata dal
/// server: qui non c'è nessun passo separato per cancellare le altre
/// richieste, arriva già risolta nel prossimo snapshot.
abstract class EncounterRepository {
  Stream<Either<Failure, ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})>>
  watchRequests(String sessionId);

  void sendRequest({required String otherPersonId});

  void respondToRequest({required String requestId, required bool accepted});

  void endMatch(String requestId);
}
