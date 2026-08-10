import 'dart:math';

import '/core/errors/exceptions.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **finta** (nessun backend vero): simula 5 persone la cui
/// presenza cambia a ogni chiamata — entrano, restano, escono — con
/// fallimento casuale di rete e la percentuale d'incontro calcolata dal
/// tempo di permanenza simulato.
class NearbyRemoteDataSourceImpl implements NearbyRemoteDataSource {
  final Random _random = Random();

  final List<_FakePresence> _people = [
    _FakePresence(
      id: '1',
      name: 'Giulia',
      distanceMeters: 4.0,
      dwellMinutes: 5,
    ),
    _FakePresence(
      id: '2',
      name: 'Marco',
      distanceMeters: 12.5,
      dwellMinutes: 3,
    ),
    _FakePresence(id: '3', name: 'Sara', distanceMeters: 19.0, dwellMinutes: 1),
    _FakePresence(id: '4', name: 'Luca', distanceMeters: 45.0, dwellMinutes: 2),
    _FakePresence(
      id: '5',
      name: 'Elena',
      distanceMeters: 150.0,
      dwellMinutes: 5,
    ),
  ];

  static const double _visibilityThresholdMinutes = 1;
  static const double _fullChanceThresholdMinutes = 5;
  static const double _leaveProbability = 0.15;
  static const double _returnProbability = 0.35;

  @override
  Future<List<NearbyPersonModel>> fetchNearbyPeople() async {
    await Future<void>.delayed(const Duration(seconds: 1));

    if (_random.nextDouble() < 0.3) {
      throw const ServerException('Server irraggiungibile');
    }

    // Simulates one server-side polling tick: presence accrues, exits, or resumes from zero.
    for (final person in _people) {
      if (person.isPresent) {
        if (_random.nextDouble() < _leaveProbability) {
          person.isPresent = false;
          person.dwellMinutes = 0;
        } else {
          person.dwellMinutes += 1;
        }
      } else if (_random.nextDouble() < _returnProbability) {
        person.isPresent = true;
        person.dwellMinutes = 0;
      }
    }

    return _people
        .where(
          (person) =>
              person.isPresent &&
              person.dwellMinutes >= _visibilityThresholdMinutes,
        )
        .map(
          (person) => NearbyPersonModel(
            id: person.id,
            name: person.name,
            photoUrl: '',
            distanceMeters: person.distanceMeters,
            meetingChancePercent:
                (person.dwellMinutes / _fullChanceThresholdMinutes * 100)
                    .clamp(0, 100)
                    .round(),
          ),
        )
        .toList();
  }
}

class _FakePresence {
  _FakePresence({
    required this.id,
    required this.name,
    required this.distanceMeters,
    required this.dwellMinutes,
  });

  final String id;
  final String name;
  final double distanceMeters;
  double dwellMinutes;
  bool isPresent = true;
}
