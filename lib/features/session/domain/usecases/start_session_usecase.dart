import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:uuid/uuid.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/profile/domain/usecases/get_profile_usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/repositories/session_repository.dart';
import 'check_selfie_has_face_usecase.dart';

class StartSessionParams extends Equatable {
  const StartSessionParams({required this.selfieBytes, this.intent});

  final Uint8List selfieBytes;
  final MeetIntent? intent;

  @override
  List<Object?> get props => [selfieBytes, intent];
}

/// Azione: vai online. Valida che ci sia un selfie e che contenga un volto
/// (compone `CheckSelfieHasFaceUseCase` come sotto-passo genuino), e che il
/// profilo sia stato compilato (compone `GetProfileUseCase`: genere e "chi
/// cerchi" servono al server per il matching) prima di salvare la sessione
/// — è la regola di business, non un dettaglio della UI.
///
/// Errori (tipizzati: la UI sceglie il testo dal tipo, vedi
/// `SessionFailureTexts`): `SelfieMissingFailure`, `ProfileMissingFailure`,
/// `NoFaceInSelfieFailure`, `FaceCheckUnavailableFailure`, o quello del
/// profilo illeggibile (`CacheFailure`).
class StartSessionUseCase
    implements UseCase<OnlineSession, StartSessionParams> {
  const StartSessionUseCase({
    required SessionRepository repository,
    required CheckSelfieHasFaceUseCase checkSelfieHasFaceUseCase,
    required GetProfileUseCase getProfileUseCase,
  }) : _repository = repository,
       _checkSelfieHasFaceUseCase = checkSelfieHasFaceUseCase,
       _getProfileUseCase = getProfileUseCase;

  final SessionRepository _repository;
  final CheckSelfieHasFaceUseCase _checkSelfieHasFaceUseCase;
  final GetProfileUseCase _getProfileUseCase;

  @override
  Future<Either<Failure, OnlineSession>> call(StartSessionParams params) async {
    if (params.selfieBytes.isEmpty) return const Left(SelfieMissingFailure());

    final profileResult = await _getProfileUseCase(const NoParams());
    final Profile profile;
    switch (profileResult) {
      case Left(:final value):
        return Left(value);
      case Right(value: null):
        return const Left(ProfileMissingFailure());
      case Right(:final value?):
        profile = value;
    }

    final faceResult = await _checkSelfieHasFaceUseCase(params.selfieBytes);

    return faceResult.match((failure) => Left(failure), (_) {
      return _repository.startSession(
        sessionId: const Uuid().v4(),
        selfieBytes: params.selfieBytes,
        profile: profile,
        intent: params.intent,
      );
    });
  }
}
