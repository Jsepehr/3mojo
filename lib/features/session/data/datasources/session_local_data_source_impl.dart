import 'dart:async';

import '/features/session/domain/entities/online_session.dart';
import 'session_local_data_source.dart';

/// Implementazione **reale**, ma solo in memoria (nessun `shared_preferences`,
/// nessun disco): la sessione vive finché vive il processo dell'app. Chiudere
/// del tutto l'app e riaprirla equivale sempre a un nuovo Start da zero —
/// coerente con "usa e getta", niente account che sopravviva alla chiusura.
class SessionLocalDataSourceImpl implements SessionLocalDataSource {
  OnlineSession? _session;
  final StreamController<OnlineSession?> _changes =
      StreamController.broadcast();

  @override
  Future<OnlineSession?> getCurrentSession() async => _session;

  @override
  Future<OnlineSession> startSession(OnlineSession session) async {
    _session = session;
    _changes.add(session);
    return session;
  }

  @override
  Future<void> endSession() async {
    _session = null;
    _changes.add(null);
  }

  // `Stream.multi`: il valore attuale e l'ascolto dei cambiamenti partono
  // nello stesso istante, senza un buco in cui un Start/End andrebbe perso.
  @override
  Stream<OnlineSession?> watchSession() => Stream.multi((controller) {
    controller.add(_session);
    final subscription = _changes.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });
}
