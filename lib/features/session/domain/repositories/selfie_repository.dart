import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';

/// Contratto per scattare e sistemare il selfie della sessione. Il selfie
/// esiste solo come byte in memoria: nessun file resta sul telefono.
abstract class SelfieRepository {
  /// Il selfie appena scattato, o `null` se l'utente ha annullato.
  Future<Either<Failure, Uint8List?>> takeSelfie();

  /// Il selfie ribaltato orizzontalmente.
  Future<Either<Failure, Uint8List>> flipHorizontally(Uint8List selfieBytes);

  /// Cancella eventuali file della fotocamera rimasti su disco.
  Future<Either<Failure, Unit>> discardLeftoverFiles();
}
