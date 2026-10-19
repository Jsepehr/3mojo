import '../entities/online_session.dart';
import '../repositories/session_repository.dart';

/// Azione: segui il ciclo di vita della sessione — la sessione attuale
/// subito, poi ogni Start/End. Le feature che parlano col server
/// (`nearby`, `encounters`, `chat`, `paywall`) partono e si fermano su
/// questi eventi invece di riprovare a vuoto con un timer da offline.
class WatchSessionUseCase {
  const WatchSessionUseCase(this._repository);

  final SessionRepository _repository;

  Stream<OnlineSession?> call() => _repository.watchSession();
}
