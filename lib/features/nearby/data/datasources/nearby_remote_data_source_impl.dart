import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '/core/errors/exceptions.dart';
import '/core/network/realtime_connection.dart';
import '/core/unlock/unlock_token_store.dart';
import '/core/utils/photo_bytes_cache.dart';
import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/nearby/data/models/presence_profile_model.dart';
import '/features/profile/domain/entities/profile.dart';
import 'nearby_remote_data_source.dart';

/// Implementazione **reale**: usa la connessione WebSocket condivisa
/// (`RealtimeConnection`, in `core/network/`) verso il backend `server/`
/// (dart_frog) — nessuna simulazione, chi vedi qui è chi ha davvero mandato
/// una posizione al server in questo momento.
///
/// La presenza "completa" (profilo + selfie) parte a ogni `welcome` del
/// server, cioè alla prima connessione **e a ogni riconnessione** in cui il
/// server ha dimenticato la sessione (`resumed: false`, grazia scaduta). Se
/// invece la riprende (`resumed: true`) e il selfie gli era già arrivato
/// (si sa dalla prima lista "vicinanze" ricevuta dopo averlo mandato), il
/// selfie non si rimanda: il server lo fissa alla nascita della sessione e
/// lo ignorerebbe, sarebbero solo centinaia di KB buttati a ogni caduta.
/// Le presenze successive portano solo posizione e token.
///
/// Il selfie si prepara una volta per sessione ([prepareSelfieForUpload]):
/// se non riesce (o resta troppo grande per il server) **non** si manda
/// l'originale — il server chiuderebbe il socket a ogni riconnessione, per
/// sempre — ma nessuna presenza, e lo stream emette
/// [SelfiePreparationException] (→ `SelfieNotUsableFailure`).
///
/// Due risposte del server riguardano lo Start stesso e arrivano come
/// errori dello stream (il repository le traduce in `Failure` tipizzati):
/// - `{"type": "rejected", "action": "presence", "reason": "invalidSelfie"}`
///   → [SelfieRejectedException]. Da lì non si manda più nessuna presenza
///   per questa sessione: il server la accetterebbe senza foto;
/// - `{"type": "error", "code": "rateLimited"}` (troppi Start dalla stessa
///   rete; poi il server chiude il socket) → [RateLimitedException];
/// - `{"type": "error", "code": "attestationRequired"}` (il server non ha
///   potuto verificare l'app su questo dispositivo, solo con la verifica in
///   `enforce`; poi chiude il socket e `RealtimeConnection` non riprova da
///   sola) → [DeviceNotVerifiedException].
class NearbyRemoteDataSourceImpl implements NearbyRemoteDataSource {
  NearbyRemoteDataSourceImpl({
    RealtimeConnection? connection,
    UnlockTokenStore? unlockTokenStore,
    Future<Uint8List> Function(Uint8List selfie)? prepareSelfie,
  }) : _connection = connection ?? RealtimeConnection.instance,
       _unlockTokenStore = unlockTokenStore ?? UnlockTokenStore.instance,
       _prepareSelfie = prepareSelfie ?? _prepareSelfieInBackground;

  final RealtimeConnection _connection;
  final UnlockTokenStore _unlockTokenStore;
  final Future<Uint8List> Function(Uint8List selfie) _prepareSelfie;
  final PhotoBytesCache _photos = PhotoBytesCache();

  // Solo ciò che il server deve sapere del profilo (vedi
  // `PresenceProfileModel`): mai la conferma d'età né il consenso.
  Map<String, dynamic> _profileFields = const {};
  String _selfieBase64 = '';
  Future<void>? _selfieReady;
  Uint8List? _selfieSource;

  // Il token di sblocco a pagamento (core/unlock/, condiviso con
  // `paywall/`), solo se si è pagato: chi non paga non manda nulla che lo
  // identifichi. Finché non c'è, il server tratta la sessione come "non
  // sbloccata", mai come un errore.
  String? _unlockToken;
  StreamSubscription<String?>? _unlockTokenChanges;
  StreamSubscription<bool>? _readySubscription;
  double? _lastLatitude;
  double? _lastLongitude;

  /// Cresce a ogni `connect`/`disconnect`: un lavoro asincrono (selfie,
  /// token) partito per una connessione vecchia non deve mandare nulla per
  /// quella nuova, né dopo un End.
  int _generation = 0;

  /// La presenza completa (col selfie) è già partita sul socket attuale:
  /// fino ad allora gli aggiornamenti di posizione aspettano (il server
  /// fissa profilo e selfie alla prima presenza).
  bool _fullPresenceSent = false;

  /// Il server ha già il selfie di questa sessione (dopo averlo mandato è
  /// arrivata una lista "vicinanze": la presenza è stata accettata). Si
  /// azzera quando il server riparte da zero (`resumed: false`).
  bool _serverHasSelfie = false;
  bool _selfieSentOnThisServerSession = false;

  /// La preparazione del selfie per questa sessione è fallita: nessuna
  /// presenza parte (vedi [_encodeSelfie]).
  bool _selfiePreparationFailed = false;
  final StreamController<int> _selfiePreparationFailures =
      StreamController.broadcast();

  /// La sessione di cui il server ha rifiutato il selfie: per lei nessuna
  /// presenza parte più (nemmeno dopo un Riprova, che richiama [connect]
  /// con la stessa sessione) — finché non c'è una sessione nuova.
  String? _sessionId;
  String? _selfieRejectedSessionId;

  @override
  Stream<List<NearbyPersonModel>> connect({
    required String sessionId,
    required double latitude,
    required double longitude,
    required Profile profile,
    MeetIntent? intent,
    required Uint8List selfieBytes,
  }) {
    final generation = ++_generation;
    _profileFields = PresenceProfileModel(
      profile: profile,
      intent: intent,
    ).toJson();
    _sessionId = sessionId;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    if (!identical(_selfieSource, selfieBytes) || _selfieReady == null) {
      _selfieSource = selfieBytes;
      _selfieBase64 = '';
      _selfiePreparationFailed = false;
      _serverHasSelfie = false;
      _selfieSentOnThisServerSession = false;
      _selfieReady = _encodeSelfie(selfieBytes, generation);
    }

    final messages = _connection.connect(sessionId);

    unawaited(_readySubscription?.cancel());
    _readySubscription = _connection.onReady.listen((resumed) {
      _fullPresenceSent = false;
      if (!resumed) {
        _serverHasSelfie = false;
        _selfieSentOnThisServerSession = false;
      }
      unawaited(_sendFullPresence(generation));
    });
    if (_connection.isReady) unawaited(_sendFullPresence(generation));
    unawaited(_attachUnlockToken(generation));

    final people = messages.transform(
      StreamTransformer<
        Map<String, dynamic>,
        List<NearbyPersonModel>
      >.fromHandlers(
        handleData: (decoded, sink) {
          switch (decoded['type']) {
            case 'nearby':
              final people = decoded['people'];
              if (people is! List) return;
              if (generation == _generation && _selfieSentOnThisServerSession) {
                _serverHasSelfie = true;
              }
              sink.add([
                for (final json in people)
                  ?NearbyPersonModel.tryFromJson(json, photos: _photos),
              ]);
            case 'rejected'
                when decoded['action'] == 'presence' &&
                    decoded['reason'] == 'invalidSelfie':
              if (generation != _generation) return;
              _selfieRejectedSessionId = sessionId;
              sink.addError(const SelfieRejectedException());
            case 'error' when decoded['code'] == 'rateLimited':
              sink.addError(const RateLimitedException());
            case 'error' when decoded['code'] == 'attestationRequired':
              sink.addError(const DeviceNotVerifiedException());
          }
        },
      ),
    );

    // Gli errori nati qui (non dal server) passano dallo stesso stream.
    return Stream.multi((controller) {
      if (_selfiePreparationFailed && generation == _generation) {
        controller.addError(const SelfiePreparationException());
      }
      final upstream = people.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      final failures = _selfiePreparationFailures.stream
          .where((failedGeneration) => failedGeneration == generation)
          .listen(
            (_) => controller.addError(const SelfiePreparationException()),
          );
      controller.onCancel = () async {
        await failures.cancel();
        await upstream.cancel();
      };
    });
  }

  Future<void> _encodeSelfie(Uint8List selfieBytes, int generation) async {
    if (selfieBytes.isEmpty) return;
    Uint8List? prepared;
    try {
      prepared = await _prepareSelfie(selfieBytes);
    } catch (_) {
      prepared = null;
    }
    // Nel frattempo è cambiato il selfie (nuovo Start) o c'è stato un End:
    // questo risultato non serve più.
    if (!identical(_selfieSource, selfieBytes)) return;
    if (prepared == null ||
        prepared.isEmpty ||
        prepared.length > maxUploadSelfieBytes) {
      // Mai l'originale: pesa troppo per il server, che chiuderebbe il
      // socket a ogni riconnessione. Niente presenza, e lo si dice.
      _selfiePreparationFailed = true;
      _selfiePreparationFailures.add(generation);
      return;
    }
    _selfieBase64 = base64Encode(prepared);
  }

  Future<void> _sendFullPresence(int generation) async {
    await _selfieReady;
    if (generation != _generation || _selfiePreparationFailed) return;
    final includeSelfie = !_serverHasSelfie;
    final sent = _sendPresence(includeSelfie: includeSelfie);
    if (sent) {
      _fullPresenceSent = true;
      if (includeSelfie && _selfieBase64.isNotEmpty) {
        _selfieSentOnThisServerSession = true;
      }
    }
  }

  Future<void> _attachUnlockToken(int generation) async {
    await _unlockTokenChanges?.cancel();
    if (generation != _generation) return;
    _unlockTokenChanges = _unlockTokenStore.changes.listen((token) {
      if (generation != _generation) return;
      _unlockToken = token;
      if (_fullPresenceSent) _sendPresence(includeSelfie: false);
    });
    final token = await _unlockTokenStore.read();
    if (generation != _generation || token == null) return;
    _unlockToken = token;
    if (_fullPresenceSent) _sendPresence(includeSelfie: false);
  }

  @override
  void updatePosition({required double latitude, required double longitude}) {
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    // Prima della presenza completa (o in riconnessione) non si manda: la
    // posizione più recente partirà con la prossima presenza completa.
    if (_fullPresenceSent) _sendPresence(includeSelfie: false);
  }

  bool _sendPresence({required bool includeSelfie}) {
    if (_selfiePreparationFailed) return false;
    if (_sessionId != null && _sessionId == _selfieRejectedSessionId) {
      return false;
    }
    final latitude = _lastLatitude;
    final longitude = _lastLongitude;
    if (latitude == null || longitude == null) return false;
    return _connection.send({
      'type': 'presence',
      'lat': latitude,
      'lng': longitude,
      ..._profileFields,
      if (includeSelfie && _selfieBase64.isNotEmpty)
        'selfieBase64': _selfieBase64,
      'unlockToken': ?_unlockToken,
    });
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    await _readySubscription?.cancel();
    _readySubscription = null;
    await _unlockTokenChanges?.cancel();
    _unlockTokenChanges = null;
    _profileFields = const {};
    _selfieBase64 = '';
    _selfieSource = null;
    _selfieReady = null;
    _unlockToken = null;
    _lastLatitude = null;
    _lastLongitude = null;
    _fullPresenceSent = false;
    _serverHasSelfie = false;
    _selfieSentOnThisServerSession = false;
    _selfiePreparationFailed = false;
    _sessionId = null;
    _selfieRejectedSessionId = null;
    _photos.clear();
    await _connection.disconnect();
  }
}

/// Il selfie com'è scattato (piena risoluzione, qualità 100, con EXIF) può
/// pesare più del limite del server (~230 KB) e contenere metadati come la
/// posizione dello scatto: qui viene raddrizzato (orientamento EXIF
/// applicato ai pixel), ridimensionato a [_maxSelfieSide] px, ripulito di
/// tutti i metadati e ricompresso. In un isolate a parte (`compute`): su un
/// JPEG da 12 MP ci vuole un istante, non deve bloccare la UI.
Future<Uint8List> _prepareSelfieInBackground(Uint8List selfie) =>
    compute(prepareSelfieForUpload, selfie);

/// Oltre questa dimensione (dopo la preparazione) il selfie non si manda:
/// **allineata** con `SelfieValidator.maxBytes` in `server/`, che lo
/// rifiuterebbe.
const maxUploadSelfieBytes = 230 * 1024;

const _maxSelfieSide = 640;
const _selfieQuality = 80;

/// Vedi [_prepareSelfieInBackground]. Pubblica (top-level) perché `compute`
/// la deve poter chiamare in un altro isolate, e per i test. Se il file non
/// si decodifica lancia `FormatException`: chi chiama non deve mai mandare
/// l'originale al suo posto.
Uint8List prepareSelfieForUpload(Uint8List selfie) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(selfie);
  } catch (_) {
    // Alcuni decoder lanciano (es. RangeError) invece di ritornare null.
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('Selfie is not a decodable image');
  }
  var image = img.bakeOrientation(decoded);
  final longestSide = image.width > image.height ? image.width : image.height;
  if (longestSide > _maxSelfieSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: _maxSelfieSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: _maxSelfieSide,
            interpolation: img.Interpolation.average,
          );
  }
  image.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(image, quality: _selfieQuality));
}
