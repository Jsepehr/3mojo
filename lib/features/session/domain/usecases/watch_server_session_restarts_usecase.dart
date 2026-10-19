import 'package:fpdart/fpdart.dart';

import '../repositories/connection_repository.dart';

/// Azione: avvisa quando il server ha **dimenticato** la sessione durante
/// una caduta (la riconnessione è arrivata dopo la grazia del server):
/// richieste, match e chat di prima non esistono più lato server, e chi
/// tiene uno stato locale deve azzerarlo.
///
/// La regola: un benvenuto con `resumed: false` che **non** è il primo
/// della sessione. Il primo è sempre `resumed: false` (la sessione nasce
/// lì) e non è un riavvio.
class WatchServerSessionRestartsUseCase {
  const WatchServerSessionRestartsUseCase(this._repository);

  final ConnectionRepository _repository;

  Stream<Unit> call() => _repository
      .watchHandshakes()
      .where((handshake) => !handshake.resumed && !handshake.isFirstOfSession)
      .map((_) => unit);
}
