import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/nearby_person.dart';
import '../../domain/usecases/watch_nearby_people_usecase.dart';

/// Stato della pagina "Vicinanze": la lista di persone, se sta caricando,
/// eventuale errore. Si abbona alla connessione persistente aperta da
/// `WatchNearbyPeopleUseCase` — il server la spinge da solo ogni volta che
/// cambia qualcosa, non serve più un timer che la richiede a intervalli.
/// Lo stream finisce sempre prima o poi (offline, End premuto, connessione
/// caduta): quando succede ci si riabbona da soli dopo una breve pausa,
/// così la lista riparte da sola appena si torna online, senza dover
/// ricreare il provider. Tiene anche a chi hai già mandato una richiesta
/// (una sola per persona, finché resta nel perimetro): l'insieme si
/// "scorda" di un id appena quella persona non è più tra i risultati, così
/// se esce e rientra puoi richiederla.
class ProNearby extends ChangeNotifier {
  ProNearby({required WatchNearbyPeopleUseCase watchNearbyPeopleUseCase})
    : _watchNearbyPeopleUseCase = watchNearbyPeopleUseCase {
    _subscribe();
  }

  static const Duration _resubscribeDelay = Duration(seconds: 3);

  final WatchNearbyPeopleUseCase _watchNearbyPeopleUseCase;

  StreamSubscription<void>? _subscription;
  Timer? _resubscribeTimer;
  List<NearbyPerson> _people = [];
  bool _isLoading = true;
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

  void _subscribe() {
    _subscription = _watchNearbyPeopleUseCase().listen(
      (result) {
        result.match(
          (failure) => _errorMessage = failure.message,
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
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
      },
      onDone: _scheduleResubscribe,
    );
  }

  void _scheduleResubscribe() {
    _resubscribeTimer = Timer(_resubscribeDelay, _subscribe);
  }

  @override
  void dispose() {
    _resubscribeTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
