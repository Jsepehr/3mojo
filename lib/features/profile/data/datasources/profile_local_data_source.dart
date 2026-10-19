import '../models/profile_model.dart';

/// Contratto per il profilo salvato sul telefono.
abstract class ProfileLocalDataSource {
  /// Il profilo salvato, o `null` se non c'è.
  Future<ProfileModel?> getProfile();

  Future<void> saveProfile(ProfileModel profile);

  Future<void> deleteProfile();

  /// `true` se questa installazione dell'app ha già fatto il primo avvio
  /// (segno tenuto in uno spazio che **sparisce** con la disinstallazione).
  Future<bool> hasInstallMarker();

  Future<void> setInstallMarker();

  /// Cancella **tutto** l'archivio cifrato dell'app (profilo, token di
  /// sblocco e ogni altra voce), non solo il profilo.
  Future<void> deleteAllSecureData();
}
