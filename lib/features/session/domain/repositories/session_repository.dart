import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/online_session.dart';

/// Contratto per leggere/avviare/terminare la sessione online corrente.
abstract class SessionRepository {
  Future<Either<Failure, OnlineSession?>> getCurrentSession();

  Future<Either<Failure, OnlineSession>> startSession({
    required String sessionId,
    required String selfiePath,
    required Uint8List selfieBytes,
    required Gender gender,
    required GenderPreference genderPreference,
  });

  Future<Either<Failure, Unit>> endSession();
}
