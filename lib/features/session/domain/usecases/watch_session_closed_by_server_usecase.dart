import 'package:fpdart/fpdart.dart';

import '../repositories/connection_repository.dart';

/// Azione: avvisa quando il server ha **chiuso** la sessione per conto suo
/// — succede quando abbastanza persone diverse l'hanno segnalata (vedi i
/// termini d'uso e `server/README.md`). Lato server la sessione non esiste
/// più e la connessione non si riapre: chi ascolta deve chiudere anche
/// quella locale (`ProSession` fa End) e dirlo all'utente
/// (`CmpConnectionNoticeListener`).
class WatchSessionClosedByServerUseCase {
  const WatchSessionClosedByServerUseCase(this._repository);

  final ConnectionRepository _repository;

  Stream<Unit> call() => _repository.watchSessionClosures().map((_) => unit);
}
