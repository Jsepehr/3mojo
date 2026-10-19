import 'package:equatable/equatable.dart';

/// Quale azione ha rifiutato il server.
enum EncounterAction { sendRequest, respondToRequest }

/// Perché il server ha rifiutato un'azione su una richiesta d'incontro
/// (stessi nomi del server, `EncounterRejectionReason`). [other] = un motivo
/// che questa versione dell'app non conosce (server più nuovo).
enum EncounterRejectionReason {
  self,
  notOnline,
  notNearby,
  locked,
  alreadyRequested,
  inMatch,
  tooManyPending,
  other,
}

/// Il server ha ricevuto un'azione ma l'ha rifiutata: la richiesta non è
/// partita (o la risposta non è valsa), e l'utente deve saperlo invece di
/// credere il contrario.
class EncounterRejection extends Equatable {
  const EncounterRejection({
    required this.action,
    required this.reason,
    this.otherPersonId,
    this.requestId,
  });

  final EncounterAction action;
  final EncounterRejectionReason reason;

  /// A chi era diretta la richiesta rifiutata ([EncounterAction.sendRequest]).
  final String? otherPersonId;

  /// Quale richiesta riguardava la risposta rifiutata
  /// ([EncounterAction.respondToRequest]).
  final String? requestId;

  @override
  List<Object?> get props => [action, reason, otherPersonId, requestId];
}
