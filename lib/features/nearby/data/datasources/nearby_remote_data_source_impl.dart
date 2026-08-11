import 'dart:math';

import '/core/errors/exceptions.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **finta** (nessun backend vero): simula 5 persone la cui
/// presenza cambia a ogni chiamata — entrano, restano, escono — con
/// fallimento casuale di rete. Il tempo di permanenza si calcola dal vero
/// orario di arrivo (`arrivedAt`), non da quante volte è stato chiamato
/// `fetchNearbyPeople()` — coerente con un vero server, che terrebbe il
/// tempo per conto suo: se qualcuno è lì da prima che tu iniziassi a
/// guardare, lo vedi già ad alta probabilità al primo caricamento.
class NearbyRemoteDataSourceImpl implements NearbyRemoteDataSource {
  final Random _random = Random();
  final List<_FakePresence> _people = _seedPeople();

  static List<_FakePresence> _seedPeople() {
    final now = DateTime.now();
    return [
      _FakePresence(
        id: '1',
        photoUrl: _photoUrlFor(1),
        distanceMeters: 4.0,
        arrivedAt: now.subtract(const Duration(minutes: 6)),
      ),
      _FakePresence(
        id: '2',
        photoUrl: _photoUrlFor(2),
        distanceMeters: 12.5,
        arrivedAt: now.subtract(const Duration(minutes: 4)),
      ),
      _FakePresence(
        id: '3',
        photoUrl: _photoUrlFor(3),
        distanceMeters: 19.0,
        arrivedAt: now.subtract(const Duration(minutes: 2)),
      ),
      _FakePresence(
        id: '4',
        photoUrl: _photoUrlFor(4),
        distanceMeters: 45.0,
        arrivedAt: now.subtract(const Duration(seconds: 90)),
      ),
      _FakePresence(
        id: '5',
        photoUrl: _photoUrlFor(5),
        distanceMeters: 150.0,
        arrivedAt: now.subtract(const Duration(minutes: 10)),
      ),
    ];
  }

  static String _photoUrlFor(int n) => 'https://i.pravatar.cc/300?img=$n';

  static const int _visibilityThresholdMinutes = 1;
  static const int _mediumChanceThresholdMinutes = 3;
  static const int _highChanceThresholdMinutes = 5;
  static const double _leaveProbability = 0.15;
  static const double _returnProbability = 0.35;

  @override
  Future<List<NearbyPersonModel>> fetchNearbyPeople() async {
    await Future<void>.delayed(const Duration(seconds: 1));

    if (_random.nextDouble() < 0.1) {
      throw const ServerException('Server irraggiungibile');
    }

    final now = DateTime.now();

    // Ogni chiamata può far entrare/uscire qualcuno dal perimetro, ma chi
    // resta accumula tempo in base al proprio orologio, non a questo tick.
    for (final person in _people) {
      if (person.isPresent) {
        if (_random.nextDouble() < _leaveProbability) {
          person.isPresent = false;
        }
      } else if (_random.nextDouble() < _returnProbability) {
        person.isPresent = true;
        person.arrivedAt = now; // arrivo fresco: si riparte da zero
      }
    }

    return _people
        .where(
          (person) =>
              person.isPresent &&
              now.difference(person.arrivedAt).inMinutes >=
                  _visibilityThresholdMinutes,
        )
        .map(
          (person) => NearbyPersonModel(
            id: person.id,
            photoUrl: person.photoUrl,
            distanceMeters: person.distanceMeters,
            meetingChance: _meetingChanceFor(now.difference(person.arrivedAt)),
          ),
        )
        .toList();
  }

  MeetingChance _meetingChanceFor(Duration dwell) {
    final minutes = dwell.inMinutes;
    if (minutes >= _highChanceThresholdMinutes) return MeetingChance.high;
    if (minutes >= _mediumChanceThresholdMinutes) return MeetingChance.medium;
    return MeetingChance.low;
  }
}

class _FakePresence {
  _FakePresence({
    required this.id,
    required this.photoUrl,
    required this.distanceMeters,
    required this.arrivedAt,
  });

  final String id;
  final String photoUrl;
  final double distanceMeters;
  DateTime arrivedAt;
  bool isPresent = true;
}
