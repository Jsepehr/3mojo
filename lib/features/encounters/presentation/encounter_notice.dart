import '/core/errors/failures.dart';
import '../domain/entities/encounter_rejection.dart';

/// Qualcosa da dire all'utente sulle richieste d'incontro, una volta sola
/// (snackbar, vedi `CmpEncounterNoticeListener`), emesso da
/// `ProEncounters.notices`. È un concetto **solo di UI** (cosa mostrare e
/// quando), non di dominio: per questo vive in `presentation/` e non in
/// `domain/entities`. Gli eventi di dominio da cui nasce (un rifiuto del
/// server, un `Failure`, un match finito) arrivano già tipizzati dagli use
/// case. I testi li sceglie la UI dal tipo: qui non c'è mai una stringa.
sealed class EncounterNotice {
  const EncounterNotice();
}

/// Il server ha confermato la richiesta (compare nello snapshot).
final class RequestSentNotice extends EncounterNotice {
  const RequestSentNotice();
}

/// Un'azione non è nemmeno partita (offline, già richiesta…) o non è mai
/// stata confermata (`RequestNotConfirmedFailure`).
final class ActionNotSentNotice extends EncounterNotice {
  const ActionNotSentNotice(this.action, this.failure);

  final EncounterAction action;
  final Failure failure;
}

/// Il server ha ricevuto un'azione e l'ha rifiutata.
final class ActionRejectedNotice extends EncounterNotice {
  const ActionRejectedNotice(this.rejection);

  final EncounterRejection rejection;
}

/// Il match attivo è finito dall'altra parte (l'altra persona l'ha chiuso
/// o è andata offline).
final class MatchEndedByPartnerNotice extends EncounterNotice {
  const MatchEndedByPartnerNotice();
}
