import '../entities/connection_status.dart';
import '../repositories/connection_repository.dart';

/// Azione: segui lo stato del collegamento col server (per l'indicatore
/// discreto "mi sto riconnettendo").
class WatchConnectionStatusUseCase {
  const WatchConnectionStatusUseCase(this._repository);

  final ConnectionRepository _repository;

  Stream<ConnectionStatus> call() => _repository.watchStatus();
}
