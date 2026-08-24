import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/repositories/session_repository.dart';
import 'check_selfie_has_face_usecase.dart';

class StartSessionParams extends Equatable {
  const StartSessionParams({
    required this.selfiePath,
    required this.selfieBytes,
    required this.gender,
    required this.genderPreference,
  });

  final String selfiePath;
  final Uint8List selfieBytes;
  final Gender gender;
  final GenderPreference genderPreference;

  @override
  List<Object?> get props => [
    selfiePath,
    selfieBytes,
    gender,
    genderPreference,
  ];
}

/// Azione: vai online. Valida che ci sia un selfie e che contenga un volto
/// (compone `CheckSelfieHasFaceUseCase` come sotto-passo genuino) prima di
/// salvare la sessione — è la regola di business, non un dettaglio della UI.
class StartSessionUseCase
    implements UseCase<OnlineSession, StartSessionParams> {
  const StartSessionUseCase({
    required SessionRepository repository,
    required CheckSelfieHasFaceUseCase checkSelfieHasFaceUseCase,
  }) : _repository = repository,
       _checkSelfieHasFaceUseCase = checkSelfieHasFaceUseCase;

  final SessionRepository _repository;
  final CheckSelfieHasFaceUseCase _checkSelfieHasFaceUseCase;

  @override
  Future<Either<Failure, OnlineSession>> call(StartSessionParams params) async {
    if (params.selfieBytes.isEmpty) {
      return const Left(ValidationFailure('Serve un selfie per andare online'));
    }

    final faceResult = await _checkSelfieHasFaceUseCase(params.selfiePath);

    return faceResult.match((failure) => Left(failure), (_) {
      return _repository.startSession(
        sessionId: const Uuid().v4(),
        selfiePath: params.selfiePath,
        selfieBytes: params.selfieBytes,
        gender: params.gender,
        genderPreference: params.genderPreference,
      );
    });
  }
}
