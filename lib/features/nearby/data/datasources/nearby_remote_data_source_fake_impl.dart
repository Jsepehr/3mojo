import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '/core/unlock/unlock_token_store.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/profile/domain/entities/profile.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **finta** (nessuna rete, nessun backend): simula 5
/// persone la cui presenza cambia a ogni tick — entrano, restano, escono.
/// Segue lo stesso protocollo del server vero:
/// - il tempo di permanenza si calcola dal vero orario di arrivo
///   (`arrivedAt`), non da quanti tick sono passati: se qualcuno è
///   "arrivato" prima che tu iniziassi a guardare, lo vedi già ad alta
///   probabilità al primo caricamento;
/// - **anche chi guarda dev'essere fermo**: per il primo minuto dopo lo
///   Start la lista è vuota (il server conta la permanenza anche di chi
///   guarda; qui la posizione finta non si sposta mai, quindi conta solo
///   il primo minuto);
/// - **nessuna distanza** verso chi chiama: la lista esce ordinata per
///   fasce di distanza di 25 m (dentro una fascia, un ordine fisso per la
///   sessione), e la distanza resta interna (ordinamento e paywall);
/// - il **paywall** è deciso qui (`isLocked`), con la stessa regola del
///   server — un terzo dei più lontani gratis (minimo 2), gli altri
///   bloccati e senza foto — a meno che ci sia un token di sblocco (in
///   modalità finta basta che esista: lo emette il paywall finto);
/// - gli id sono diversi a ogni sessione, come gli pseudonimi del server.
///
/// Nessuna foto (placeholder in UI), niente immagini di rete — la modalità
/// finta funziona anche a modem staccato.
class NearbyRemoteDataSourceFakeImpl implements NearbyRemoteDataSource {
  NearbyRemoteDataSourceFakeImpl({UnlockTokenStore? unlockTokenStore})
    : _unlockTokenStore = unlockTokenStore ?? UnlockTokenStore.instance;

  final UnlockTokenStore _unlockTokenStore;
  final Random _random = Random();
  List<_FakePresence> _people = const [];
  StreamController<List<NearbyPersonModel>>? _controller;
  StreamSubscription<String?>? _unlockTokenChanges;
  Timer? _timer;
  String _idPrefix = '';
  bool _isUnlocked = false;
  DateTime _connectedAt = DateTime.now();

  static const Duration _tickInterval = Duration(seconds: 3);
  static const int _visibilityThresholdMinutes = 1;
  static const double _rankBandMeters = 25;
  static const int _mediumChanceThresholdMinutes = 3;
  static const int _highChanceThresholdMinutes = 5;
  static const double _leaveProbability = 0.1;
  static const double _returnProbability = 0.25;
  static const double _freeFraction = 1 / 3;
  static const int _minFreeCount = 2;

  static List<_FakePresence> _seedPeople() {
    final now = DateTime.now();
    return [
      _FakePresence(
        index: 1,
        distanceMeters: 4,
        arrivedAt: now.subtract(const Duration(minutes: 6)),
        intent: MeetIntent.chat,
        languages: const ['it', 'en'],
        visibleGender: Gender.female,
      ),
      _FakePresence(
        index: 2,
        distanceMeters: 12.5,
        arrivedAt: now.subtract(const Duration(minutes: 4)),
        intent: MeetIntent.openToAnything,
        languages: const ['it'],
      ),
      _FakePresence(
        index: 3,
        distanceMeters: 19,
        arrivedAt: now.subtract(const Duration(minutes: 2)),
        intent: MeetIntent.friendship,
        languages: const ['es', 'en'],
        visibleGender: Gender.male,
      ),
      _FakePresence(
        index: 4,
        distanceMeters: 45,
        arrivedAt: now.subtract(const Duration(seconds: 90)),
        visibleGender: Gender.nonBinary,
      ),
      // Dentro il raggio di 100 m del server: oltre, il server vero non la
      // manderebbe mai.
      _FakePresence(
        index: 5,
        distanceMeters: 80,
        arrivedAt: now.subtract(const Duration(minutes: 10)),
        intent: MeetIntent.meetPeople,
        languages: const ['fr'],
      ),
    ];
  }

  @override
  Stream<List<NearbyPersonModel>> connect({
    required String sessionId,
    required double latitude,
    required double longitude,
    required Profile profile,
    MeetIntent? intent,
    required Uint8List selfieBytes,
  }) {
    final prefix = 'fake${sessionId.hashCode.toRadixString(16)}';
    final existing = _controller;
    if (existing != null && !existing.isClosed && prefix == _idPrefix) {
      scheduleMicrotask(_emit);
      return existing.stream;
    }

    unawaited(existing?.close());
    _idPrefix = prefix;
    _connectedAt = DateTime.now();
    _people = _seedPeople();
    final controller = StreamController<List<NearbyPersonModel>>.broadcast();
    _controller = controller;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
    unawaited(_watchUnlock());

    scheduleMicrotask(_emit);
    return controller.stream;
  }

  Future<void> _watchUnlock() async {
    await _unlockTokenChanges?.cancel();
    _unlockTokenChanges = _unlockTokenStore.changes.listen((token) {
      _isUnlocked = token != null;
      _emit();
    });
    try {
      _isUnlocked = await _unlockTokenStore.read() != null;
    } catch (_) {
      _isUnlocked = false;
    }
    _emit();
  }

  @override
  void updatePosition({required double latitude, required double longitude}) {
    // La posizione finta è fissa per ogni persona seminata: nessuna azione.
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    await _unlockTokenChanges?.cancel();
    _unlockTokenChanges = null;
    await _controller?.close();
    _controller = null;
    _idPrefix = '';
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
    final viewerStayedPut =
        now.difference(_connectedAt).inMinutes >= _visibilityThresholdMinutes;
    int band(_FakePresence p) => (p.distanceMeters / _rankBandMeters).floor();
    int tiebreak(_FakePresence p) => Object.hash(_idPrefix, p.index);
    final visible =
        _people
            .where(
              (person) =>
                  viewerStayedPut &&
                  person.isPresent &&
                  now.difference(person.arrivedAt).inMinutes >=
                      _visibilityThresholdMinutes,
            )
            .toList()
          ..sort((a, b) {
            final byBand = band(a).compareTo(band(b));
            return byBand != 0 ? byBand : tiebreak(a).compareTo(tiebreak(b));
          });

    final freeCount = _isUnlocked
        ? visible.length
        : min(
            visible.length,
            max((visible.length * _freeFraction).floor(), _minFreeCount),
          );
    // I più lontani sono quelli gratis — per distanza esatta, come sul
    // server, non per posizione nella lista (ordinata per fasce).
    final freeIndexes =
        ([...visible]
              ..sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters)))
            .take(freeCount)
            .map((p) => p.index)
            .toSet();

    controller.add([
      for (var i = 0; i < visible.length; i++)
        NearbyPersonModel(
          id: '$_idPrefix-${visible[i].index}',
          meetingChance: _meetingChanceFor(
            now.difference(visible[i].arrivedAt),
          ),
          isLocked: !freeIndexes.contains(visible[i].index),
          intent: visible[i].intent,
          languages: visible[i].languages,
          visibleGender: visible[i].visibleGender,
        ),
    ]);
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
    required this.index,
    required this.distanceMeters,
    required this.arrivedAt,
    this.intent,
    this.languages = const [],
    this.visibleGender,
  });

  final int index;

  /// Solo interna: ordina la lista e decide il paywall, mai esposta.
  final double distanceMeters;
  final MeetIntent? intent;
  final List<String> languages;
  final Gender? visibleGender;
  DateTime arrivedAt;
  bool isPresent = true;
}
