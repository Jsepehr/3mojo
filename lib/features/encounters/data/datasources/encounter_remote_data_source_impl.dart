import 'dart:typed_data';

import '/core/errors/exceptions.dart';
import '/core/network/realtime_connection.dart';
import '/core/utils/photo_bytes_cache.dart';
import '../../domain/entities/encounter_request.dart';
import '../models/encounter_rejection_model.dart';
import '../models/encounter_request_model.dart';
import 'encounter_remote_data_source.dart';

/// Implementazione **reale**: usa la connessione WebSocket condivisa
/// (`RealtimeConnection`, la stessa di `nearby`) verso il backend `server/`
/// — nessuna simulazione, chi vedi qui è chi ha davvero mandato/ricevuto
/// una richiesta su questa sessione.
///
/// **Selfie una volta sola**: il server manda il selfie della controparte
/// solo la prima volta per ogni richiesta su ogni socket; negli snapshot
/// successivi manca. Qui si tiene quello già ricevuto per id di richiesta
/// (solo in memoria, solo per le richieste in attesa o accettate ancora
/// presenti) e lo si rimette nel model.
class EncounterRemoteDataSourceImpl implements EncounterRemoteDataSource {
  EncounterRemoteDataSourceImpl({RealtimeConnection? connection})
    : _connection = connection ?? RealtimeConnection.instance;

  /// Quante richieste possono portare un selfie insieme: il tetto del
  /// server alle pendenti (`EncounterStore`: 20 in entrata + 5 in uscita)
  /// più il match accettato. La cache delle foto non deve buttarne fuori
  /// nessuna mentre sono ancora a schermo.
  static const maxRequestsWithSelfie = 20 + 5 + 1;

  final RealtimeConnection _connection;
  final PhotoBytesCache _photos = PhotoBytesCache(
    maxEntries: maxRequestsWithSelfie,
  );
  final Map<String, Uint8List> _selfieByRequestId = {};

  @override
  Stream<EncounterSnapshotModel> watchRequests(String sessionId) {
    final messages = _connection.connect(sessionId);

    return messages.where((decoded) => decoded['type'] == 'encounters').map((
      decoded,
    ) {
      List<EncounterRequestModel> parse(String key) {
        final raw = decoded[key];
        if (raw is! List) return const [];
        return [
          for (final json in raw)
            ?EncounterRequestModel.tryFromJson(json, photos: _photos),
        ];
      }

      final incoming = parse('incoming');
      final outgoing = parse('outgoing');
      final stillShown = <String>{
        for (final request in [...incoming, ...outgoing])
          if (request.status == EncounterRequestStatus.pending ||
              request.status == EncounterRequestStatus.accepted)
            request.id,
      };
      _selfieByRequestId.removeWhere((id, _) => !stillShown.contains(id));
      return (
        incoming: incoming.map(_withKnownSelfie).toList(),
        outgoing: outgoing.map(_withKnownSelfie).toList(),
      );
    });
  }

  EncounterRequestModel _withKnownSelfie(EncounterRequestModel request) {
    if (request.status != EncounterRequestStatus.pending &&
        request.status != EncounterRequestStatus.accepted) {
      return request;
    }
    final received = request.otherSelfieBytes;
    if (received != null) {
      _selfieByRequestId[request.id] = received;
      return request;
    }
    final known = _selfieByRequestId[request.id];
    return known == null ? request : request.withOtherSelfie(known);
  }

  @override
  Stream<EncounterRejectionModel> watchRejections(String sessionId) =>
      _connection.connect(sessionId).handleError((Object _) {}).expand((
        decoded,
      ) {
        final rejection = EncounterRejectionModel.tryFromJson(decoded);
        return rejection == null
            ? const <EncounterRejectionModel>[]
            : [rejection];
      });

  void _send(Map<String, dynamic> message) {
    if (!_connection.send(message)) {
      throw const ServerException('Non connesso al server: non inviato');
    }
  }

  @override
  void sendRequest({required String otherPersonId}) =>
      _send({'type': 'sendEncounterRequest', 'toPersonId': otherPersonId});

  @override
  void respondToRequest({required String requestId, required bool accepted}) =>
      _send({
        'type': 'respondToEncounterRequest',
        'requestId': requestId,
        'accepted': accepted,
      });

  @override
  void endMatch(String requestId) =>
      _send({'type': 'endMatch', 'requestId': requestId});

  @override
  Future<void> reset() async {
    _photos.clear();
    _selfieByRequestId.clear();
  }
}
