import 'dart:async';

import 'blocked_people_local_data_source.dart';

/// Implementazione in memoria (nessun disco, nessuna cifratura necessaria:
/// non sopravvive nemmeno alla chiusura dell'app).
class BlockedPeopleLocalDataSourceImpl implements BlockedPeopleLocalDataSource {
  final Set<String> _blocked = {};
  final StreamController<Set<String>> _changes = StreamController.broadcast();
  int _reportsSent = 0;

  @override
  Set<String> get blockedPersonIds => Set.unmodifiable(_blocked);

  @override
  Stream<Set<String>> watchBlockedPersonIds() => Stream.multi((controller) {
    controller.add(blockedPersonIds);
    final subscription = _changes.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });

  @override
  void addBlocked(String personId) {
    if (_blocked.add(personId)) _changes.add(blockedPersonIds);
  }

  @override
  int get reportsSent => _reportsSent;

  @override
  void incrementReportsSent() => _reportsSent++;

  @override
  void clear() {
    _reportsSent = 0;
    if (_blocked.isEmpty) return;
    _blocked.clear();
    _changes.add(blockedPersonIds);
  }
}
