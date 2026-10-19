import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/profile.dart';

/// Contratto per leggere/salvare/cancellare il profilo sul telefono.
abstract class ProfileRepository {
  /// Il profilo salvato, o `null` se non è ancora stato compilato.
  Future<Either<Failure, Profile?>> getProfile();

  Future<Either<Failure, Unit>> saveProfile(Profile profile);

  Future<Either<Failure, Unit>> deleteProfile();

  /// `true` al primo avvio di questa installazione dell'app.
  Future<Either<Failure, bool>> isFirstLaunchAfterInstall();

  /// Ricorda che questa installazione ha già fatto il primo avvio.
  Future<Either<Failure, Unit>> markFirstLaunchDone();

  /// Cancella tutto ciò che l'app tiene nell'archivio cifrato del telefono
  /// (profilo compreso).
  Future<Either<Failure, Unit>> deleteAllSecureData();
}
