import 'package:flutter/foundation.dart';

import '/core/usecases/usecase.dart';
import '../../domain/entities/profile.dart';
import '../../domain/usecases/get_my_profile_usecase.dart';
import '../../domain/usecases/update_profile_usecase.dart';

class ProProfile extends ChangeNotifier {
  ProProfile({
    required GetMyProfileUseCase getMyProfileUseCase,
    required UpdateProfileUseCase updateProfileUseCase,
  }) : _getMyProfileUseCase = getMyProfileUseCase,
       _updateProfileUseCase = updateProfileUseCase {
    loadProfile();
  }

  final GetMyProfileUseCase _getMyProfileUseCase;
  final UpdateProfileUseCase _updateProfileUseCase;

  Profile? _profile;
  bool _isLoading = false;
  String? _errorMessage;

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    final result = await _getMyProfileUseCase(const NoParams());
    result.match(
      (failure) {
        _errorMessage = failure.message;
      },
      (profile) {
        _profile = profile;
        _errorMessage = null;
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateProfile(Profile profile) async {
    final result = await _updateProfileUseCase(profile);
    result.match(
      (failure) {
        _errorMessage = failure.message;
      },
      (updated) {
        _profile = updated;
        _errorMessage = null;
      },
    );
    notifyListeners();
  }
}
