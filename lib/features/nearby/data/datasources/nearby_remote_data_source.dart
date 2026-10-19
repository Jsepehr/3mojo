import 'dart:typed_data';

import '/features/nearby/data/models/nearby_person_model.dart';
import '/features/profile/domain/entities/profile.dart';

/// Contratto verso il backend `server/` (dart_frog): un canale persistente
/// (WebSocket) invece di richieste separate — la presenza (con profilo e
/// selfie) si manda a ogni (ri)connessione e poi a ogni `updatePosition`, e
/// la lista "vicinanze" arriva dal server ogni volta che cambia qualcosa,
/// già ordinata e con il flag del paywall, senza doverla richiedere.
abstract class NearbyRemoteDataSource {
  /// Apre la connessione per `sessionId`; appena il server risponde (e a
  /// ogni riconnessione) manda la presenza con profilo, selfie e posizione.
  /// Lo stream ritornato emette la lista aggiornata ogni volta che il server
  /// la spinge; se la connessione cade emette un errore (`ServerException`)
  /// ma **non** si chiude: la riconnessione è automatica (vedi
  /// `RealtimeConnection`). Finisce solo con [disconnect].
  Stream<List<NearbyPersonModel>> connect({
    required String sessionId,
    required double latitude,
    required double longitude,
    required Profile profile,
    MeetIntent? intent,
    required Uint8List selfieBytes,
  });

  /// Manda un aggiornamento di posizione sulla connessione già aperta.
  /// Se in questo momento non si può mandare (in riconnessione) non lancia:
  /// la posizione viene ricordata e parte con la prossima presenza, alla
  /// riconnessione.
  void updatePosition({required double latitude, required double longitude});

  /// Chiude la connessione — equivalente del bottone End: il server chiude
  /// subito la sessione e mi toglie dalla vista di tutti. Dimentica anche
  /// selfie, profilo e token tenuti in memoria per le presenze.
  Future<void> disconnect();
}
