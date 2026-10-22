import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/report_reason.dart';
import '../repositories/safety_repository.dart';
import 'block_person_usecase.dart';

class ReportPersonParams extends Equatable {
  const ReportPersonParams({required this.personId, required this.reason});

  final String personId;
  final ReportReason reason;

  @override
  List<Object?> get props => [personId, reason];
}

/// Azione: segnala una persona per un motivo della lista chiusa
/// ([ReportReason]) — e, insieme, la **blocca** (lo fa il server alla
/// ricezione, come [BlockPersonUseCase]).
///
/// Regola: al più [maxReportsPerSession] segnalazioni per sessione, la
/// stessa del server (`ModerationStore.maxReportsPerSession`: cambiarle
/// insieme), contro chi segnalerebbe a raffica. Oltre, la segnalazione non
/// parte ma la persona viene **comunque bloccata** (compone
/// [BlockPersonUseCase]: chi ha un problema con qualcuno deve poterlo
/// allontanare sempre) e l'esito è `Left(TooManyReportsFailure)`, perché
/// la UI dica che la segnalazione non è stata mandata.
///
/// Cosa fa il server con le segnalazioni (chiusura automatica dopo quelle
/// di più persone, record di moderazione conservato 30 giorni) è scritto
/// nei termini d'uso e in `server/README.md`.
class ReportPersonUseCase {
  const ReportPersonUseCase(this._repository, this._blockPersonUseCase);

  static const maxReportsPerSession = 5;

  final SafetyRepository _repository;
  final BlockPersonUseCase _blockPersonUseCase;

  Either<Failure, Unit> call(ReportPersonParams params) {
    if (params.personId.isEmpty) {
      return const Left(ValidationFailure('Unknown person'));
    }
    if (_repository.reportsSentThisSession >= maxReportsPerSession) {
      return _blockPersonUseCase(
        params.personId,
      ).flatMap((_) => const Left(TooManyReportsFailure(maxReportsPerSession)));
    }
    return _repository.reportPerson(
      personId: params.personId,
      reason: params.reason,
    );
  }
}
