import '../models/profile_model.dart';
import 'profile_local_data_source.dart';

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  ProfileModel _profile = const ProfileModel(
    id: 'me',
    name: 'Il tuo nome',
    age: 25,
    bio: 'Scrivi qualcosa su di te',
    photoUrl: '',
  );

  @override
  Future<ProfileModel> getMyProfile() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _profile;
  }

  @override
  Future<ProfileModel> updateProfile(ProfileModel profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _profile = profile;
    return _profile;
  }
}
