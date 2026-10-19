import '/core/utils/photo_bytes_cache.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/profile/domain/entities/profile.dart';

/// Versione di `NearbyPerson` che sa leggersi da un elemento di `people` nel
/// messaggio `{"type": "nearby", ...}` del WebSocket `/ws` — il server
/// espone `personId` (uno pseudonimo valido solo per questo telefono),
/// `meetingChance`, `locked` (paywall, deciso dal server) e, se non
/// bloccato, `selfieBase64`. Nessuna distanza.
///
/// Il selfie viene decodificato **qui, una volta**, e non a ogni `build`
/// (vedi `PhotoBytesCache`).
class NearbyPersonModel extends NearbyPerson {
  const NearbyPersonModel({
    required super.id,
    required super.meetingChance,
    super.photoBytes,
    super.isLocked,
    super.intent,
    super.languages,
    super.visibleGender,
  });

  /// Lancia `FormatException` se mancano i campi indispensabili o hanno un
  /// valore sconosciuto (es. uno stadio di probabilità nuovo, da un server
  /// più recente dell'app). Per una lista usare [tryFromJson].
  factory NearbyPersonModel.fromJson(
    Map<String, dynamic> json, {
    PhotoBytesCache? photos,
  }) {
    final id = json['personId'];
    final chance = _enumOrNull(MeetingChance.values, json['meetingChance']);
    if (id is! String || id.isEmpty || chance == null) {
      throw FormatException('Persona vicina non valida', json);
    }
    final isLocked = json['locked'] == true;
    final rawLanguages = json['languages'];
    return NearbyPersonModel(
      id: id,
      meetingChance: chance,
      isLocked: isLocked,
      photoBytes: isLocked
          ? null
          : (photos ?? PhotoBytesCache(maxEntries: 0)).decode(
              json['selfieBase64'],
            ),
      intent: _enumOrNull(MeetIntent.values, json['intent']),
      languages: rawLanguages is List
          ? rawLanguages.whereType<String>().toList(growable: false)
          : const [],
      visibleGender: _enumOrNull(Gender.values, json['gender']),
    );
  }

  /// Come [NearbyPersonModel.fromJson], ma `null` invece di un'eccezione:
  /// un elemento non valido si salta, non fa fallire tutta la lista.
  static NearbyPersonModel? tryFromJson(
    Object? json, {
    PhotoBytesCache? photos,
  }) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return NearbyPersonModel.fromJson(json, photos: photos);
    } on FormatException {
      return null;
    }
  }
}

/// Un valore sconosciuto (es. un server più nuovo dell'app) non deve far
/// fallire tutta la lista: semplicemente non si mostra.
T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
