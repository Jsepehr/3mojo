import 'dart:typed_data';

import '/features/nearby/data/models/nearby_person_model.dart';

/// Contratto verso il backend `server/` (dart_frog, in esecuzione in
/// locale): un canale persistente (WebSocket) invece di richieste separate
/// — la presenza si manda una volta alla connessione e poi a ogni
/// `updatePosition`, e la lista "vicinanze" arriva dal server ogni volta
/// che cambia qualcosa, senza doverla richiedere di nuovo.
abstract class NearbyRemoteDataSource {
  /// Apre la connessione per `sessionId`, mandando subito il profilo e la
  /// posizione come primo aggiornamento di presenza. Lo stream ritornato
  /// emette la lista aggiornata ogni volta che il server la spinge, e
  /// finisce (con un errore, se la causa è quella) alla disconnessione.
  Stream<List<NearbyPersonModel>> connect({
    required String sessionId,
    required double latitude,
    required double longitude,
    required String gender,
    required String genderPreference,
    required Uint8List selfieBytes,
  });

  /// Manda un aggiornamento di posizione sulla connessione già aperta,
  /// riusando il profilo mandato al `connect`.
  void updatePosition({required double latitude, required double longitude});

  /// Chiude la connessione — equivalente del bottone End: il server se ne
  /// accorge subito e mi toglie dalla vista di tutti.
  Future<void> disconnect();
}
