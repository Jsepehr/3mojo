import 'dart:async';

import 'package:flutter/foundation.dart';

import '/core/usecases/usecase.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/usecases/get_nearby_people_usecase.dart';

/// Stato della pagina "Vicinanze": la lista di persone, se sta caricando,
/// eventuale errore. Ricarica su richiesta (pull-to-refresh) e da sola con
/// un timer che simula il controllo periodico del server: ogni minuto per i
/// primi 5 minuti (la situazione cambia in fretta), poi rallenta — 2, 4, 8
/// minuti — fino a stabilizzarsi su un controllo ogni 12 minuti, invece di
/// continuare a martellare il server con la stessa frequenza per sempre.
/// Tiene anche a chi hai già mandato una richiesta (una sola per persona,
/// finché resta nel perimetro): l'insieme si "scorda" di un id appena quella
/// persona non è più tra i risultati, così se esce e rientra puoi richiederla.
class ProNearby extends ChangeNotifier {
  ProNearby({required GetNearbyPeopleUseCase getNearbyPeopleUseCase})
    : _getNearbyPeopleUseCase = getNearbyPeopleUseCase {
    loadNearbyPeople();
    _scheduleNextRefresh();
  }

  final GetNearbyPeopleUseCase _getNearbyPeopleUseCase;

  static const List<int> _refreshIntervalsMinutes = [1, 1, 1, 1, 1, 2, 4, 8];
  static const int _maxRefreshIntervalMinutes = 12;

  Timer? _refreshTimer;
  int _refreshCount = 0;
  List<NearbyPerson> _people = [];
  bool _isLoading = false;
  String? _errorMessage;
  final Set<String> _requestedPersonIds = {};

  List<NearbyPerson> get people => _people;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool hasRequested(String personId) => _requestedPersonIds.contains(personId);

  void markRequested(String personId) {
    _requestedPersonIds.add(personId);
    notifyListeners();
  }

  void _scheduleNextRefresh() {
    final minutes = _refreshCount < _refreshIntervalsMinutes.length
        ? _refreshIntervalsMinutes[_refreshCount]
        : _maxRefreshIntervalMinutes;
    _refreshCount++;

    _refreshTimer = Timer(Duration(minutes: minutes), () async {
      await loadNearbyPeople();
      _scheduleNextRefresh();
    });
  }

  Future<void> loadNearbyPeople() async {
    _isLoading = true;
    // Deferred: the constructor calls this synchronously, which can run
    // during another widget's build (e.g. the first time this provider is
    // read) — notifying immediately would try to rebuild mid-build.
    scheduleMicrotask(notifyListeners);

    final result = await _getNearbyPeopleUseCase(const NoParams());
    result.match(
      (failure) {
        _errorMessage = failure.message;
      },
      (people) {
        _people = people;
        _errorMessage = null;
        _requestedPersonIds.retainWhere(
          (id) => people.any((person) => person.id == id),
        );
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
