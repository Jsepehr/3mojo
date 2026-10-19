import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../repositories/selfie_repository.dart';

/// Azione: ribalta orizzontalmente il selfie. Molte fotocamere frontali
/// (soprattutto Android) lo salvano speculare: decide l'utente, col bottone
/// sopra la foto.
class FlipSelfieUseCase implements UseCase<Uint8List, Uint8List> {
  const FlipSelfieUseCase(this._repository);

  final SelfieRepository _repository;

  @override
  Future<Either<Failure, Uint8List>> call(Uint8List selfieBytes) {
    if (selfieBytes.isEmpty) {
      return Future.value(const Left(SelfieMissingFailure()));
    }
    return _repository.flipHorizontally(selfieBytes);
  }
}
