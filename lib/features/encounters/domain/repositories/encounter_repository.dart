import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/encounter_proposal.dart';
import '../entities/encounter_rejection.dart';
import '../entities/encounter_request.dart';

/// Contratto per inviare/ricevere/rispondere a richieste d'interesse.
/// L'esclusività ("un solo match attivo alla volta") è applicata dal
/// server: qui non c'è nessun passo separato per cancellare le altre
/// richieste, arriva già risolta nel prossimo snapshot.
///
/// Le azioni ritornano subito: `Right(unit)` se sono partite verso il
/// server, `Left(ConnectionFailure)` se in questo momento non si può
/// (offline, in riconnessione) — la UI può dire "non inviato". Il server
/// può comunque rifiutarle (persona non più vicina, già chiesta, match in
/// corso…): l'esito vero è sempre il prossimo snapshot.
abstract class EncounterRepository {
  Stream<
    Either<
      Failure,
      ({List<EncounterRequest> incoming, List<EncounterRequest> outgoing})
    >
  >
  watchRequests(String sessionId);

  /// Le azioni che il server ha ricevuto ma rifiutato, col motivo (persona
  /// non più vicina, già richiesta, match in corso…). Non fallisce: i
  /// problemi di connessione arrivano già da [watchRequests].
  Stream<EncounterRejection> watchRejections(String sessionId);

  /// [proposal] è cosa si propone (lista chiusa): sul filo va solo il
  /// codice.
  Either<Failure, Unit> sendRequest({
    required String otherPersonId,
    required EncounterProposal proposal,
  });

  Either<Failure, Unit> respondToRequest({
    required String requestId,
    required bool accepted,
  });

  Either<Failure, Unit> endMatch(String requestId);

  /// Dimentica lo stato della sessione appena finita (da chiamare a End).
  Future<Either<Failure, Unit>> clearSessionState();
}
