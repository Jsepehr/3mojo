import '/features/session/domain/entities/online_session.dart';

/// Contratto per persistere la sessione online sul dispositivo.
abstract class SessionLocalDataSource {
  Future<OnlineSession?> getCurrentSession();
  Future<OnlineSession> startSession(OnlineSession session);
  Future<void> endSession();

  /// La sessione attuale subito, poi a ogni [startSession]/[endSession].
  Stream<OnlineSession?> watchSession();
}
