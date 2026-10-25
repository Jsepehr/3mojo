import '../models/profile_model.dart';
import 'profile_local_data_source.dart';

/// Implementazione **finta**, solo in memoria: niente disco, niente
/// Keychain/Keystore. La usa la demo dichiarata (`DemoScope`), partendo dal
/// suo profilo neutro ([initial]): il profilo vero, cifrato sul telefono,
/// la demo non lo legge e non lo scrive mai.
class ProfileLocalDataSourceFakeImpl implements ProfileLocalDataSource {
  ProfileLocalDataSourceFakeImpl({ProfileModel? initial}) : _profile = initial;

  ProfileModel? _profile;

  @override
  Future<ProfileModel?> getProfile() async => _profile;

  @override
  Future<void> saveProfile(ProfileModel profile) async => _profile = profile;

  @override
  Future<void> deleteProfile() async => _profile = null;

  @override
  Future<bool> hasInstallMarker() async => true;

  @override
  Future<void> setInstallMarker() async {}

  @override
  Future<void> deleteAllSecureData() async => _profile = null;
}
