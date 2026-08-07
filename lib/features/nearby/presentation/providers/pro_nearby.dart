import 'package:flutter/foundation.dart';

import '/core/usecases/usecase.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/usecases/get_nearby_people_usecase.dart';

class ProNearby extends ChangeNotifier {
  ProNearby({required GetNearbyPeopleUseCase getNearbyPeopleUseCase})
    : _getNearbyPeopleUseCase = getNearbyPeopleUseCase {
    loadNearbyPeople();
  }

  final GetNearbyPeopleUseCase _getNearbyPeopleUseCase;

  List<NearbyPerson> _people = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<NearbyPerson> get people => _people;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadNearbyPeople() async {
    _isLoading = true;
    notifyListeners();

    final result = await _getNearbyPeopleUseCase(const NoParams());
    result.match(
      (failure) {
        _errorMessage = failure.message;
      },
      (people) {
        _people = people;
        _errorMessage = null;
      },
    );

    _isLoading = false;
    notifyListeners();
  }
}
