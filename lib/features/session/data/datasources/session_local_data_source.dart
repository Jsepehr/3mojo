import '../../domain/entities/online_session.dart';

abstract class SessionLocalDataSource {
  Future<OnlineSession?> getCurrentSession();
  Future<OnlineSession> startSession(OnlineSession session);
  Future<void> endSession();
}
