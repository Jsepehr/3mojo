import 'dart:async';

import 'package:threemojo_app/core/errors/exceptions.dart';
import 'package:threemojo_app/features/safety/data/datasources/blocked_people_local_data_source_impl.dart';
import 'package:threemojo_app/features/safety/data/datasources/safety_remote_data_source.dart';
import 'package:threemojo_app/features/safety/data/models/safety_rejection_model.dart';
import 'package:threemojo_app/features/safety/data/repositories/safety_repository_impl.dart';
import 'package:threemojo_app/features/safety/domain/entities/report_reason.dart';

/// Datasource remoto di blocca/segnala pilotabile dal test: ricorda cosa è
/// partito e, con [offline], fa come la connessione non pronta
/// (`ServerException`). I rifiuti del server si spingono con [rejections].
class FakeSafetyRemoteDataSource implements SafetyRemoteDataSource {
  bool offline = false;
  final blocked = <String>[];
  final reported = <(String, ReportReason)>[];
  int resets = 0;
  final rejections = StreamController<SafetyRejectionModel>.broadcast();

  @override
  void block(String personId) {
    if (offline) throw const ServerException('not connected');
    blocked.add(personId);
  }

  @override
  void report({required String personId, required ReportReason reason}) {
    if (offline) throw const ServerException('not connected');
    reported.add((personId, reason));
  }

  @override
  Stream<SafetyRejectionModel> watchRejections(String sessionId) =>
      rejections.stream;

  @override
  Future<void> reset() async => resets++;
}

typedef FakeSafety = ({
  FakeSafetyRemoteDataSource remote,
  BlockedPeopleLocalDataSourceImpl local,
  SafetyRepositoryImpl repository,
});

/// Il repository vero (bloccati in memoria compresi) sopra il datasource
/// remoto finto.
FakeSafety buildSafety() {
  final remote = FakeSafetyRemoteDataSource();
  final local = BlockedPeopleLocalDataSourceImpl();
  return (
    remote: remote,
    local: local,
    repository: SafetyRepositoryImpl(remote, local),
  );
}
