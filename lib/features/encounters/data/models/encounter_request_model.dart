import 'dart:typed_data';

import '/core/utils/photo_bytes_cache.dart';
import '/features/profile/domain/entities/profile.dart';
import '../../domain/entities/encounter_proposal.dart';
import '../../domain/entities/encounter_request.dart';

/// Versione di `EncounterRequest` che sa leggersi dal JSON spinto dal
/// server sulla connessione WebSocket condivisa — il server espone
/// `otherPersonId` (lo pseudonimo dell'altra persona, valido solo per
/// questo telefono) e, solo per richieste in attesa o accettate,
/// `otherSelfieBase64` (decodificato qui una volta sola, vedi
/// `PhotoBytesCache`) e il profilo visibile. `proposal` (cosa ha proposto
/// chi ha chiesto) c'è sempre; un codice mancante o sconosciuto (server più
/// nuovo dell'app) diventa `EncounterProposal.fallback` — non fa saltare la
/// richiesta.
class EncounterRequestModel extends EncounterRequest {
  const EncounterRequestModel({
    required super.id,
    required super.otherPersonId,
    required super.status,
    super.proposal,
    super.otherSelfieBytes,
    super.otherIntent,
    super.otherLanguages,
    super.otherVisibleGender,
  });

  /// Lancia `FormatException` se mancano i campi indispensabili o lo stato
  /// è sconosciuto (es. uno stato nuovo da un server più recente dell'app).
  /// Per uno snapshot usare [tryFromJson].
  factory EncounterRequestModel.fromJson(
    Map<String, dynamic> json, {
    PhotoBytesCache? photos,
  }) {
    final id = json['id'];
    final otherPersonId = json['otherPersonId'];
    final status = _enumOrNull(EncounterRequestStatus.values, json['status']);
    if (id is! String || otherPersonId is! String || status == null) {
      throw FormatException('Richiesta non valida', json);
    }
    final rawLanguages = json['otherLanguages'];
    return EncounterRequestModel(
      id: id,
      otherPersonId: otherPersonId,
      status: status,
      proposal:
          _enumOrNull(EncounterProposal.values, json['proposal']) ??
          EncounterProposal.fallback,
      otherSelfieBytes: (photos ?? PhotoBytesCache(maxEntries: 0)).decode(
        json['otherSelfieBase64'],
      ),
      otherIntent: _enumOrNull(MeetIntent.values, json['otherIntent']),
      otherLanguages: rawLanguages is List
          ? rawLanguages.whereType<String>().toList(growable: false)
          : const [],
      otherVisibleGender: _enumOrNull(Gender.values, json['otherGender']),
    );
  }

  /// Come [EncounterRequestModel.fromJson], ma `null` invece di
  /// un'eccezione: una richiesta non valida si salta, non fa fallire tutto
  /// lo snapshot.
  static EncounterRequestModel? tryFromJson(
    Object? json, {
    PhotoBytesCache? photos,
  }) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return EncounterRequestModel.fromJson(json, photos: photos);
    } on FormatException {
      return null;
    }
  }

  /// La stessa richiesta col selfie dell'altra persona già noto (il server
  /// lo manda una volta sola per socket, vedi
  /// `EncounterRemoteDataSourceImpl`).
  EncounterRequestModel withOtherSelfie(Uint8List bytes) =>
      EncounterRequestModel(
        id: id,
        otherPersonId: otherPersonId,
        otherSelfieBytes: bytes,
        status: status,
        proposal: proposal,
        otherIntent: otherIntent,
        otherLanguages: otherLanguages,
        otherVisibleGender: otherVisibleGender,
      );

  /// La stessa richiesta con un altro stato (tutto il resto invariato).
  EncounterRequestModel withStatus(EncounterRequestStatus status) =>
      EncounterRequestModel(
        id: id,
        otherPersonId: otherPersonId,
        otherSelfieBytes: otherSelfieBytes,
        status: status,
        proposal: proposal,
        otherIntent: otherIntent,
        otherLanguages: otherLanguages,
        otherVisibleGender: otherVisibleGender,
      );
}

/// Un valore sconosciuto (es. un server più nuovo dell'app) non deve far
/// fallire tutta la lista: semplicemente non si mostra.
T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
