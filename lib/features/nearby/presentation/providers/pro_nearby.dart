import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/entities/online_session.dart';
import '/features/session/domain/usecases/watch_session_usecase.dart';
import '../../domain/entities/background_location_notice.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/usecases/open_app_settings_usecase.dart';
import '../../domain/usecases/open_location_settings_usecase.dart';
import '../../domain/usecases/watch_nearby_people_usecase.dart';

/// Stato della pagina "Vicinanze": la lista di persone, se sta caricando,
/// eventuale errore. Si abbona alla connessione persistente aperta da
/// `WatchNearbyPeopleUseCase` — il server la spinge da solo ogni volta che
/// cambia qualcosa.
///
/// **Lavora solo da online**, guidato dal ciclo di vita della sessione
/// (`WatchSessionUseCase`): parte a ogni Start, si ferma e si azzera
/// esplicitamente a End (nessun timer che riprova a vuoto da offline).
/// Le cadute di rete non chiudono lo stream (la riconnessione è automatica
/// in `RealtimeConnection`): arrivano come `ConnectionFailure` e, se una
/// lista c'è già, la lista **resta** (l'indicatore "mi sto riconnettendo"
/// è `CmpConnectionBanner`); solo senza nessuna lista si mostra l'errore
/// a tutta pagina con Riprova. L'unico caso in cui lo stream finisce da
/// online è un problema di posizione (GPS spento, permesso negato): lì si
/// riprova da soli dopo una pausa, così tornando dalle impostazioni la
/// lista riparte senza toccare nulla.
///
/// Chi hai già richiesto non sta più qui: lo decide `ProEncounters` dallo
/// snapshot delle richieste (la fonte di verità è il server).
///
/// L'errore è esposto come `Failure` (non come stringa): è la UI
/// (`CmpNearbyErrorState`) a scegliere icona e testi tradotti dal suo tipo.
/// Tre errori riguardano lo Start stesso e **restano** finché la sessione
/// non cambia: `SelfieRejectedByServerFailure` (il server non ha accettato
/// il selfie: gli altri non ti vedono, nemmeno se poi arriva una lista),
/// `SelfieNotUsableFailure` (il selfie non si è potuto preparare per
/// l'invio: nessuna presenza parte) e
/// `TooManyStartsFailure` (la caduta di connessione che lo segue non lo
/// sostituisce con un generico "sei offline").
///
/// I testi della notifica Android della posizione in background
/// ([setBackgroundLocationNotice]) sono **obbligatori** lungo tutta la
/// catena fino al datasource GPS (nessun testo di riserva nel data layer):
/// finché la UI non li ha passati, l'ascolto aspetta.
class ProNearby extends ChangeNotifier {
  ProNearby({
    required WatchSessionUseCase watchSessionUseCase,
    required WatchNearbyPeopleUseCase watchNearbyPeopleUseCase,
    required OpenLocationSettingsUseCase openLocationSettingsUseCase,
    required OpenAppSettingsUseCase openAppSettingsUseCase,
  }) : _watchNearbyPeopleUseCase = watchNearbyPeopleUseCase,
       _openLocationSettingsUseCase = openLocationSettingsUseCase,
       _openAppSettingsUseCase = openAppSettingsUseCase {
    _sessionSubscription = watchSessionUseCase().listen(_onSession);
  }

  static const Duration _locationRetryDelay = Duration(seconds: 3);

  /// Quanto resta visibile il "sto riprovando" dopo un tap su Riprova,
  /// anche se la risposta arriva prima: senza, un nuovo fallimento in
  /// pochi millisecondi sembrerebbe un bottone che non fa niente.
  static const Duration _retryFeedback = Duration(milliseconds: 900);

  final WatchNearbyPeopleUseCase _watchNearbyPeopleUseCase;
  final OpenLocationSettingsUseCase _openLocationSettingsUseCase;
  final OpenAppSettingsUseCase _openAppSettingsUseCase;

  late final StreamSubscription<OnlineSession?> _sessionSubscription;
  StreamSubscription<void>? _subscription;
  Timer? _locationRetryTimer;
  Timer? _retryFeedbackTimer;
  String? _sessionId;
  List<NearbyPerson> _people = [];
  bool _hasList = false;
  bool _isLoading = true;
  bool _isRetrying = false;
  Failure? _failure;
  BackgroundLocationNotice? _backgroundNotice;

  /// La sessione è online ma l'ascolto aspetta i testi della notifica.
  bool _waitingForNotice = false;

  List<NearbyPerson> get people => _people;
  bool get isLoading => _isLoading;

  /// Perché la lista non si può mostrare ora, o `null` se va tutto bene.
  Failure? get failure => _failure;

  /// `true` per un istante dopo [retry] — per un feedback sul bottone.
  bool get isRetrying => _isRetrying;

  /// I testi tradotti della notifica Android che accompagna la posizione in
  /// background: li imposta la UI (che ha gli ARB) prima dello Start, e
  /// valgono dalla prossima apertura dell'ascolto. Se una sessione è già
  /// online e aspettava solo loro, l'ascolto parte ora.
  void setBackgroundLocationNotice(BackgroundLocationNotice notice) {
    _backgroundNotice = notice;
    if (_waitingForNotice && _sessionId != null) _subscribe();
  }

  /// Riprova subito: riapre l'ascolto, e il collegamento (se stava
  /// aspettando il prossimo tentativo automatico) riparte all'istante.
  void retry() {
    if (_isRetrying || _sessionId == null) return;
    _isRetrying = true;
    notifyListeners();
    _retryFeedbackTimer = Timer(_retryFeedback, () {
      _isRetrying = false;
      notifyListeners();
    });
    _subscribe();
  }

  /// Per `LocationDisabledFailure`: apre le impostazioni della
  /// localizzazione. Al ritorno nell'app si riprova da soli.
  Future<void> openLocationSettings() =>
      _openLocationSettingsUseCase(const NoParams());

  /// Per `LocationPermissionFailure`: apre le impostazioni di questa app.
  Future<void> openAppSettings() => _openAppSettingsUseCase(const NoParams());

  void _onSession(OnlineSession? session) {
    final sessionId = session?.sessionId;
    if (sessionId == _sessionId) return;

    _stop();
    _sessionId = sessionId;
    if (sessionId != null) _subscribe();
    notifyListeners();
  }

  /// Ferma tutto e dimentica la lista: la prossima sarà di una sessione
  /// nuova.
  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    _waitingForNotice = false;
    _people = [];
    _hasList = false;
    _failure = null;
    _isLoading = true;
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = null;
    _locationRetryTimer?.cancel();
    final notice = _backgroundNotice;
    _waitingForNotice = notice == null;
    if (notice == null) return;
    _subscription = _watchNearbyPeopleUseCase(backgroundNotice: notice).listen(
      _onResult,
      onError: (Object error) {
        _failure = UnexpectedFailure(error.toString());
        _isLoading = false;
        notifyListeners();
      },
      onDone: _onDone,
    );
  }

  void _onResult(Either<Failure, List<NearbyPerson>> result) {
    if (_failure is SelfieRejectedByServerFailure ||
        _failure is SelfieNotUsableFailure) {
      return;
    }
    switch (result) {
      case Left(value: NotOnlineFailure()):
        // La sessione è finita mentre si caricava: ci pensa l'evento di
        // fine sessione ad azzerare tutto.
        _failure = null;
        _isLoading = true;
      case Left(value: ConnectionFailure()) when _hasList:
        // Caduta con una lista già a schermo: resta com'è, la
        // riconnessione è automatica (vedi `CmpConnectionBanner`).
        break;
      case Left(value: ConnectionFailure())
          when _failure is TooManyStartsFailure:
        // Il server chiude il socket subito dopo `rateLimited`: resta la
        // spiegazione vera, non un generico "sei offline".
        break;
      case Left(:final value):
        _failure = value;
        _isLoading = false;
      case Right(:final value):
        _people = value;
        _hasList = true;
        _failure = null;
        _isLoading = false;
    }
    notifyListeners();
  }

  void _onDone() {
    _subscription = null;
    final failure = _failure;
    final isLocationProblem =
        failure is LocationDisabledFailure ||
        failure is LocationPermissionFailure;
    if (_sessionId != null && isLocationProblem) {
      _locationRetryTimer = Timer(_locationRetryDelay, _subscribe);
    }
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    _locationRetryTimer?.cancel();
    _retryFeedbackTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
