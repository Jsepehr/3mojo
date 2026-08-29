import '../../domain/entities/encounter_request.dart';

/// Versione di `EncounterRequest` che sa leggersi dal JSON spinto dal
/// server sulla connessione WebSocket condivisa — il server espone
/// `otherSessionId` (l'id, effimero, dell'altra sessione coinvolta) e
/// `otherSelfieBase64` (il suo selfie, preso fresco da `SessionStore` a
/// ogni snapshot, mai conservato nella richiesta), qui tradotti in
/// `otherPersonId` e `otherSelfiePath` (una data URI che la UI può passare
/// direttamente a `Image.memory`).
class EncounterRequestModel extends EncounterRequest {
  const EncounterRequestModel({
    required super.id,
    required super.otherPersonId,
    required super.otherSelfiePath,
    required super.status,
  });

  factory EncounterRequestModel.fromJson(Map<String, dynamic> json) {
    final selfieBase64 = json['otherSelfieBase64'] as String? ?? '';
    return EncounterRequestModel(
      id: json['id'] as String,
      otherPersonId: json['otherSessionId'] as String,
      otherSelfiePath: selfieBase64.isEmpty
          ? ''
          : 'data:image/jpeg;base64,$selfieBase64',
      status: EncounterRequestStatus.values.byName(json['status'] as String),
    );
  }
}
