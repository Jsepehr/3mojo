import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/features/profile/domain/entities/profile.dart';
import '../entities/online_session.dart';

/// Contratto per leggere/avviare/terminare la sessione online corrente.
abstract class SessionRepository {
  Future<Either<Failure, OnlineSession?>> getCurrentSession();

  Future<Either<Failure, OnlineSession>> startSession({
    required String sessionId,
    required Uint8List selfieBytes,
    required Profile profile,
    MeetIntent? intent,
  });

  Future<Either<Failure, Unit>> endSession();

  /// La sessione attuale subito (anche `null`), poi a ogni Start/End: è il
  /// segnale del ciclo di vita a cui si agganciano le altre feature, per
  /// lavorare solo da online e fermarsi esplicitamente a End. Vive in
  /// memoria: non può fallire.
  Stream<OnlineSession?> watchSession();
}
