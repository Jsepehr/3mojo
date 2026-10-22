import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/entities/report_reason.dart';
import '../../domain/entities/safety_rejection.dart';
import '../../domain/usecases/block_person_usecase.dart';
import '../../domain/usecases/report_person_usecase.dart';
import '../../domain/usecases/watch_safety_rejections_usecase.dart';

/// Stato UI di "Blocca"/"Segnala": manda le azioni (le regole stanno in
/// `BlockPersonUseCase` e `ReportPersonUseCase`) e ritorna subito l'esito
/// a chi le ha chiamate, che lo mostra (`CmpPersonSafetyMenuButton`). I
/// rifiuti che arrivano dopo dal server ([rejections]) li mostra
/// `CmpSafetyNoticeListener`.
///
/// Nascondere i bloccati non è compito suo: lo fanno `ProNearby` e
/// `ProEncounters` dai bloccati della sessione (`WatchBlockedPeopleUseCase`).
///
/// **Lavora solo da online**, guidato dal ciclo di vita della sessione: a
/// ogni Start si abbona ai rifiuti, a End smette.
class ProSafety extends ChangeNotifier {
  ProSafety({
    required WatchSessionUseCase watchSessionUseCase,
    required BlockPersonUseCase blockPersonUseCase,
    required ReportPersonUseCase reportPersonUseCase,
    required WatchSafetyRejectionsUseCase watchSafetyRejectionsUseCase,
  }) : _blockPersonUseCase = blockPersonUseCase,
       _reportPersonUseCase = reportPersonUseCase,
       _watchSafetyRejectionsUseCase = watchSafetyRejectionsUseCase {
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
  }

  final BlockPersonUseCase _blockPersonUseCase;
  final ReportPersonUseCase _reportPersonUseCase;
  final WatchSafetyRejectionsUseCase _watchSafetyRejectionsUseCase;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  StreamSubscription<SafetyRejection>? _rejectionsSubscription;
  final StreamController<SafetyRejection> _rejections =
      StreamController.broadcast();
  String? _sessionId;

  /// I blocchi/segnalazioni rifiutati dal server, uno per evento.
  Stream<SafetyRejection> get rejections => _rejections.stream;

  /// Blocca [personId]. `Right` = partito (la persona è già nascosta).
  Either<Failure, Unit> block(String personId) => _blockPersonUseCase(personId);

  /// Segnala (e blocca) [personId]. `Left(TooManyReportsFailure)` = la
  /// segnalazione non è partita, ma il blocco sì.
  Either<Failure, Unit> report(String personId, ReportReason reason) =>
      _reportPersonUseCase(
        ReportPersonParams(personId: personId, reason: reason),
      );

  void _onSession(OnlineSession? session) {
    final sessionId = session?.sessionId;
    if (sessionId == _sessionId) return;
    _sessionId = sessionId;
    _rejectionsSubscription?.cancel();
    _rejectionsSubscription = null;
    if (sessionId == null) return;
    _rejectionsSubscription = _watchSafetyRejectionsUseCase().listen((
      rejection,
    ) {
      if (!_rejections.isClosed) _rejections.add(rejection);
    });
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    _rejectionsSubscription?.cancel();
    _rejections.close();
    super.dispose();
  }
}
