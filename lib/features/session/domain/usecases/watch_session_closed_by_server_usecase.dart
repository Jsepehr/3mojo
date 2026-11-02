import '../entities/session_closure_reason.dart';
import '../repositories/connection_repository.dart';

/// Azione: avvisa quando il server ha **chiuso** la sessione per conto suo
/// — succede quando abbastanza persone diverse l'hanno segnalata (vedi i
/// termini d'uso e `server/README.md`) o quando il server si spegne per un
/// deploy: il [SessionClosureReason] dell'evento dice quale. Lato server la sessione non esiste
/// più e la connessione non si riapre: chi ascolta deve chiudere anche
/// quella locale (`ProSession` fa End) e dirlo all'utente
/// (`CmpConnectionNoticeListener`).
class WatchSessionClosedByServerUseCase {
  const WatchSessionClosedByServerUseCase(this._repository);

  final ConnectionRepository _repository;

  Stream<SessionClosureReason> call() => _repository.watchSessionClosures();
}
