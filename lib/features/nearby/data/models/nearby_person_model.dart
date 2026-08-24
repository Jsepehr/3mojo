import '/features/nearby/domain/entities/nearby_person.dart';

/// Versione di `NearbyPerson` che sa leggersi dal JSON di `GET /nearby` —
/// il server espone `sessionId` (l'id, effimero, di un'altra sessione
/// online ora) e `selfieBase64` (il selfie così com'è arrivato al server,
/// mai decodificato lì), qui tradotti in `id` e `photoUrl` (una data URI
/// che la UI può passare direttamente a `Image.memory`).
class NearbyPersonModel extends NearbyPerson {
  const NearbyPersonModel({
    required super.id,
    required super.photoUrl,
    required super.distanceMeters,
    required super.meetingChance,
  });

  factory NearbyPersonModel.fromJson(Map<String, dynamic> json) {
    final selfieBase64 = json['selfieBase64'] as String? ?? '';
    return NearbyPersonModel(
      id: json['sessionId'] as String,
      photoUrl: selfieBase64.isEmpty
          ? ''
          : 'data:image/jpeg;base64,$selfieBase64',
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      meetingChance: MeetingChance.values.byName(
        json['meetingChance'] as String,
      ),
    );
  }
}
