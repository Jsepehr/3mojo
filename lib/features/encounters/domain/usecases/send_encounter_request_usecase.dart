import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/encounter_proposal.dart';
import '../entities/encounter_request.dart';
import '../repositories/encounter_repository.dart';
import 'has_requested_person_usecase.dart';

class SendEncounterRequestParams extends Equatable {
  const SendEncounterRequestParams({
    required this.otherPersonId,
    required this.knownRequests,
    this.proposal = EncounterProposal.fallback,
    this.awaitingPersonIds = const {},
  });

  final String otherPersonId;

  /// Cosa si propone (lista chiusa, scelta nella tendina).
  final EncounterProposal proposal;

  /// Le richieste (in entrata e in uscita) dell'ultimo snapshot del server.
  final List<EncounterRequest> knownRequests;

  /// Persone a cui una richiesta è appena partita e che lo snapshot non
  /// mostra ancora.
  final Set<String> awaitingPersonIds;

  @override
  List<Object?> get props => [
    otherPersonId,
    proposal,
    knownRequests,
    awaitingPersonIds,
  ];
}

/// Azione: manda una richiesta d'interesse a una persona vista in
/// "Vicinanze". Regola di business: **una sola richiesta a testa** per
/// sessione (`HasRequestedPersonUseCase`) — se c'è già, non parte nemmeno
/// (`AlreadyRequestedFailure`). `Right` = è partita verso il server;
/// `Left(ConnectionFailure)` = non è partita (offline, in riconnessione).
/// Il server può ancora rifiutarla (persona non più vicina, troppe
/// richieste…): quello arriva da `WatchEncounterRejectionsUseCase`, l'esito
/// positivo col prossimo snapshot.
class SendEncounterRequestUseCase {
  const SendEncounterRequestUseCase(
    this._repository, {
    HasRequestedPersonUseCase hasRequestedPersonUseCase =
        const HasRequestedPersonUseCase(),
  }) : _hasRequestedPersonUseCase = hasRequestedPersonUseCase;

  final EncounterRepository _repository;
  final HasRequestedPersonUseCase _hasRequestedPersonUseCase;

  Either<Failure, Unit> call(SendEncounterRequestParams params) {
    final alreadyRequested = _hasRequestedPersonUseCase(
      params.otherPersonId,
      requests: params.knownRequests,
      awaitingPersonIds: params.awaitingPersonIds,
    );
    if (alreadyRequested) {
      return const Left(
        AlreadyRequestedFailure('A request with this person already exists'),
      );
    }
    return _repository.sendRequest(
      otherPersonId: params.otherPersonId,
      proposal: params.proposal,
    );
  }
}
