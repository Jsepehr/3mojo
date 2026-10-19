import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/core/errors/exceptions.dart';
import '../models/profile_model.dart';
import 'profile_local_data_source.dart';

/// Implementazione **reale**: profilo salvato **cifrato** con
/// `flutter_secure_storage`, non in `shared_preferences`. Genere + "chi
/// cerchi" lasciano dedurre l'orientamento sessuale: in chiaro li leggerebbe
/// chiunque prenda in mano il telefono, e finirebbero nei backup cloud.
///
/// - Android: chiave nel Keystore, che non lascia mai il dispositivo (più
///   `allowBackup="false"` nel manifest);
/// - iOS: Keychain `first_unlock_this_device`, escluso da backup e
///   migrazione su un altro iPhone. **Ma il Keychain sopravvive alla
///   disinstallazione dell'app**: per questo esiste il segno di
///   installazione ([hasInstallMarker]) in `shared_preferences`
///   (`UserDefaults` su iOS), che invece sparisce con l'app — vedi
///   `WipeDataFromPreviousInstallUseCase`.
///
/// I messaggi delle eccezioni sono tecnici e non contengono mai l'errore
/// grezzo del sistema: non arrivano mai a schermo (la UI sceglie il testo
/// dal tipo di `Failure`).
class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  static const _profileKey = 'profile';
  static const _installMarkerKey = 'app_install_marker';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<ProfileModel?> getProfile() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _profileKey);
    } catch (e) {
      throw CacheException('Profile unreadable (${e.runtimeType})');
    }
    if (raw == null) return null;

    try {
      return ProfileModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Formato vecchio o corrotto: meglio ricompilare il profilo che
      // bloccare l'app.
      await deleteProfile();
      return null;
    }
  }

  @override
  Future<void> saveProfile(ProfileModel profile) async {
    try {
      await _storage.write(
        key: _profileKey,
        value: jsonEncode(profile.toJson()),
      );
    } catch (e) {
      throw CacheException('Profile not saved (${e.runtimeType})');
    }
  }

  @override
  Future<void> deleteProfile() async {
    try {
      await _storage.delete(key: _profileKey);
    } catch (e) {
      throw CacheException('Profile not deleted (${e.runtimeType})');
    }
  }

  @override
  Future<bool> hasInstallMarker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_installMarkerKey) ?? false;
    } catch (e) {
      throw CacheException('Install marker unreadable (${e.runtimeType})');
    }
  }

  @override
  Future<void> setInstallMarker() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_installMarkerKey, true);
    } catch (e) {
      throw CacheException('Install marker not saved (${e.runtimeType})');
    }
  }

  @override
  Future<void> deleteAllSecureData() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw CacheException('Secure storage not wiped (${e.runtimeType})');
    }
  }
}
