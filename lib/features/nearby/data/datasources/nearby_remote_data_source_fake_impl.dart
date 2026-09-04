import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete, nessun backend): simula 5
/// persone la cui presenza cambia a ogni tick — entrano, restano, escono.
/// Il tempo di permanenza si calcola dal vero orario di arrivo
/// (`arrivedAt`), non da quanti tick sono passati — coerente con un vero
/// server, che terrebbe il tempo per conto suo: se qualcuno è "arrivato"
/// prima che tu iniziassi a guardare, lo vedi già ad alta probabilità al
/// primo caricamento. Nessuna foto: `photoUrl` resta vuota (placeholder in
/// UI), niente immagini di rete — la modalità finta funziona anche a modem
/// staccato.
class NearbyRemoteDataSourceFakeImpl implements NearbyRemoteDataSource {
  final Random _random = Random();
  final List<_FakePresence> _people = _seedPeople();
  StreamController<List<NearbyPersonModel>>? _controller;
  Timer? _timer;

  static const Duration _tickInterval = Duration(seconds: 3);
  static const int _visibilityThresholdMinutes = 1;
  static const int _mediumChanceThresholdMinutes = 3;
  static const int _highChanceThresholdMinutes = 5;
  static const double _leaveProbability = 0.1;
  static const double _returnProbability = 0.25;

  static List<_FakePresence> _seedPeople() {
    final now = DateTime.now();
    return [
      _FakePresence(
        id: 'fake-1',
        distanceMeters: 4,
        arrivedAt: now.subtract(const Duration(minutes: 6)),
      ),
      _FakePresence(
        id: 'fake-2',
        distanceMeters: 12.5,
        arrivedAt: now.subtract(const Duration(minutes: 4)),
      ),
      _FakePresence(
        id: 'fake-3',
        distanceMeters: 19,
        arrivedAt: now.subtract(const Duration(minutes: 2)),
      ),
      _FakePresence(
        id: 'fake-4',
        distanceMeters: 45,
        arrivedAt: now.subtract(const Duration(seconds: 90)),
      ),
      _FakePresence(
        id: 'fake-5',
        distanceMeters: 150,
        arrivedAt: now.subtract(const Duration(minutes: 10)),
      ),
    ];
  }

  @override
  Stream<List<NearbyPersonModel>> connect({
    required String sessionId,
    required double latitude,
    required double longitude,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  }) {
    final controller = StreamController<List<NearbyPersonModel>>.broadcast();
    _controller = controller;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());

    scheduleMicrotask(_emit);
    return controller.stream;
  }

  @override
  void updatePosition({required double latitude, required double longitude}) {
    // La posizione finta è fissa per ogni persona seminata: nessuna azione.
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    await _controller?.close();
    _controller = null;
  }

  void _tick() {
    final now = DateTime.now();
    for (final person in _people) {
      if (person.isPresent) {
        if (_random.nextDouble() < _leaveProbability) {
          person.isPresent = false;
        }
      } else if (_random.nextDouble() < _returnProbability) {
        person.isPresent = true;
        person.arrivedAt = now;
      }
    }
    _emit();
  }

  void _emit() {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;

    final now = DateTime.now();
    final people = _people
        .where(
          (person) =>
              person.isPresent &&
              now.difference(person.arrivedAt).inMinutes >=
                  _visibilityThresholdMinutes,
        )
        .map(
          (person) => NearbyPersonModel(
            id: person.id,
            photoUrl: '',
            distanceMeters: person.distanceMeters,
            meetingChance: _meetingChanceFor(now.difference(person.arrivedAt)),
          ),
        )
        .toList();
    controller.add(people);
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
    required this.distanceMeters,
    required this.arrivedAt,
  });

  final String id;
  final double distanceMeters;
  DateTime arrivedAt;
  bool isPresent = true;
}
