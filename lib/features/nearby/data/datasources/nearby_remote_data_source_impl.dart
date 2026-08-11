import 'dart:math';

import '/core/errors/exceptions.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **finta** (nessun backend vero): simula 5 persone la cui
/// presenza cambia a ogni chiamata — entrano, restano, escono — con
/// fallimento casuale di rete e lo stadio di probabilità d'incontro
/// calcolato dal tempo di permanenza simulato.
class NearbyRemoteDataSourceImpl implements NearbyRemoteDataSource {
  final Random _random = Random();

  // Tutti partono da 0: appena entrati nel raggio di 100 metri, nessuno può
  // già essere a probabilità media o alta — ci si arriva solo restando.
  final List<_FakePresence> _people = [
    _FakePresence(
      id: '1',
      photoUrl: _photoUrlFor(1),
      distanceMeters: 4.0,
      dwellMinutes: 0,
    ),
    _FakePresence(
      id: '2',
      photoUrl: _photoUrlFor(2),
      distanceMeters: 12.5,
      dwellMinutes: 0,
    ),
    _FakePresence(
      id: '3',
      photoUrl: _photoUrlFor(3),
      distanceMeters: 19.0,
      dwellMinutes: 0,
    ),
    _FakePresence(
      id: '4',
      photoUrl: _photoUrlFor(4),
      distanceMeters: 45.0,
      dwellMinutes: 0,
    ),
    _FakePresence(
      id: '5',
      photoUrl: _photoUrlFor(5),
      distanceMeters: 150.0,
      dwellMinutes: 0,
    ),
  ];

  static String _photoUrlFor(int n) => 'https://i.pravatar.cc/300?img=$n';

  static const double _visibilityThresholdMinutes = 1;
  static const double _mediumChanceThresholdMinutes = 3;
  static const double _highChanceThresholdMinutes = 5;
  static const double _leaveProbability = 0.15;
  static const double _returnProbability = 0.35;

  @override
  Future<List<NearbyPersonModel>> fetchNearbyPeople() async {
    await Future<void>.delayed(const Duration(seconds: 1));

    if (_random.nextDouble() < 0.1) {
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
            photoUrl: person.photoUrl,
            distanceMeters: person.distanceMeters,
            meetingChance: _meetingChanceFor(person.dwellMinutes),
          ),
        )
        .toList();
  }

  MeetingChance _meetingChanceFor(double dwellMinutes) {
    if (dwellMinutes >= _highChanceThresholdMinutes) return MeetingChance.high;
    if (dwellMinutes >= _mediumChanceThresholdMinutes) {
      return MeetingChance.medium;
    }
    return MeetingChance.low;
  }
}

class _FakePresence {
  _FakePresence({
    required this.id,
    required this.photoUrl,
    required this.distanceMeters,
    required this.dwellMinutes,
  });

  final String id;
  final String photoUrl;
  final double distanceMeters;
  double dwellMinutes;
  bool isPresent = true;
}
