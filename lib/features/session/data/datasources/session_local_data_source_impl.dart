import '/features/session/domain/entities/online_session.dart';
import 'session_local_data_source.dart';

/// Implementazione **reale**, ma solo in memoria (nessun `shared_preferences`,
/// nessun disco): la sessione vive finché vive il processo dell'app. Chiudere
/// del tutto l'app e riaprirla equivale sempre a un nuovo Start da zero —
/// coerente con "usa e getta", niente account che sopravviva alla chiusura.
class SessionLocalDataSourceImpl implements SessionLocalDataSource {
  OnlineSession? _session;

  @override
  Future<OnlineSession?> getCurrentSession() async => _session;

  @override
  Future<OnlineSession> startSession(OnlineSession session) async {
    _session = session;
    return session;
  }

  @override
  Future<void> endSession() async {
    _session = null;
  }
}
