import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/report_reason.dart';
import '../entities/safety_rejection.dart';

/// Contratto per bloccare e segnalare le persone di questa sessione. Gli
/// id sono gli pseudonimi ricevuti dal server (validi solo per questo
/// telefono): il server li traduce e applica il blocco **nei due sensi**.
///
/// Le azioni ritornano subito: `Right(unit)` se sono partite verso il
/// server — e da quel momento la persona è anche fra i bloccati di questa
/// sessione ([watchBlockedPersonIds]), così sparisce subito, prima ancora
/// del prossimo snapshot —, `Left(ConnectionFailure)` se in questo momento
/// non si può (offline, in riconnessione): non parte nulla e nessuno è
/// nascosto. Segnalare implica bloccare.
///
/// Tutto **solo in memoria** e solo per la sessione in corso
/// ([clearSessionState] a End): non esistono id permanenti, quindi un
/// blocco non può sopravvivere a End/nuovo Start.
abstract class SafetyRepository {
  Either<Failure, Unit> blockPerson(String personId);

  Either<Failure, Unit> reportPerson({
    required String personId,
    required ReportReason reason,
  });

  /// Quante segnalazioni sono partite in questa sessione.
  int get reportsSentThisSession;

  /// I bloccati di questa sessione: subito quelli attuali, poi a ogni
  /// cambiamento.
  Stream<Set<String>> watchBlockedPersonIds();

  /// I blocchi/segnalazioni che il server ha ricevuto ma rifiutato.
  Stream<SafetyRejection> watchRejections(String sessionId);

  /// Dimentica bloccati e conteggio della sessione appena finita (End).
  Future<Either<Failure, Unit>> clearSessionState();
}
