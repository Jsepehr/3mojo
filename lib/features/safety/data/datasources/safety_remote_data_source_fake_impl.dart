import 'dart:async';

import '../../domain/entities/report_reason.dart';
import '../../domain/entities/safety_rejection.dart';
import '../models/safety_rejection_model.dart';
import 'safety_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete): accetta blocchi e segnalazioni
/// applicando le stesse regole del server che il client può vedere — oltre
/// [maxReportsPerSession] segnalazioni nella sessione torna `rejected`
/// `tooManyReports` (il blocco vale comunque). Lo sparire della persona da
/// "Vicinanze" e dalle richieste, e la chiusura del match, li simula il
/// client stesso nascondendo i bloccati della sessione (`ProNearby`,
/// `ProEncounters`): i datasource finti di quelle feature non sanno nulla
/// dei blocchi, come non sa nulla il telefono di chi viene bloccato.
class SafetyRemoteDataSourceFakeImpl implements SafetyRemoteDataSource {
  /// Lo stesso tetto del server (`ModerationStore.maxReportsPerSession`).
  static const maxReportsPerSession = 5;

  final StreamController<SafetyRejectionModel> _rejections =
      StreamController.broadcast();
  final Set<String> _reported = {};

  @override
  void block(String personId) {}

  @override
  void report({required String personId, required ReportReason reason}) {
    if (_reported.contains(personId)) return; // doppione: ignorato.
    if (_reported.length >= maxReportsPerSession) {
      _rejections.add(
        SafetyRejectionModel(
          action: SafetyAction.report,
          reason: SafetyRejectionReason.tooManyReports,
          personId: personId,
        ),
      );
      return;
    }
    _reported.add(personId);
  }

  @override
  Stream<SafetyRejectionModel> watchRejections(String sessionId) =>
      _rejections.stream;

  @override
  Future<void> reset() async => _reported.clear();
}
