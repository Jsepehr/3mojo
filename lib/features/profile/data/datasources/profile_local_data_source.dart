import '../models/profile_model.dart';

abstract class ProfileLocalDataSource {
  Future<ProfileModel> getMyProfile();
  Future<ProfileModel> updateProfile(ProfileModel profile);
}
