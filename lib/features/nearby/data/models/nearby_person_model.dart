import 'dart:typed_data';

import '/core/utils/photo_bytes_cache.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/session/domain/entities/meet_place.dart';

/// Versione di `NearbyPerson` che sa leggersi da un elemento di `people` nel
/// messaggio `{"type": "nearby", ...}` del WebSocket `/ws` — il server
/// espone `personId` (uno pseudonimo valido solo per questo telefono),
/// `meetingChance`, `locked` (paywall, deciso dal server) e, se non
/// bloccato, `selfieBase64`. Nessuna distanza.
///
/// Il selfie viene decodificato **qui, una volta**, e non a ogni `build`
/// (vedi `PhotoBytesCache`). **Il server manda la foto di una persona una
/// volta sola per connessione** (poi omette `selfieBase64`, che pesa fino a
/// ~230 KB): quella ricevuta si tiene in [knownPhotos] per `personId`, e una
/// lista senza foto per una persona già vista riusa quella. Una persona di
/// cui non è mai arrivata una foto resta senza (`photoBytes` nullo), come
/// una bloccata dal paywall.
class NearbyPersonModel extends NearbyPerson {
  const NearbyPersonModel({
    required super.id,
    required super.meetingChance,
    super.photoBytes,
    super.isLocked,
    super.place,
    super.languages,
    super.visibleGender,
  });

  /// Lancia `FormatException` se mancano i campi indispensabili o hanno un
  /// valore sconosciuto (es. uno stadio di probabilità nuovo, da un server
  /// più recente dell'app). Per una lista usare [tryFromJson].
  factory NearbyPersonModel.fromJson(
    Map<String, dynamic> json, {
    PhotoBytesCache? photos,
    Map<String, Uint8List>? knownPhotos,
  }) {
    final id = json['personId'];
    final chance = _enumOrNull(MeetingChance.values, json['meetingChance']);
    if (id is! String || id.isEmpty || chance == null) {
      throw FormatException('Persona vicina non valida', json);
    }
    final isLocked = json['locked'] == true;
    Uint8List? photo;
    if (!isLocked) {
      photo = (photos ?? PhotoBytesCache(maxEntries: 0)).decode(
        json['selfieBase64'],
      );
      if (photo != null) {
        knownPhotos?[id] = photo;
      } else {
        photo = knownPhotos?[id];
      }
    }
    final rawLanguages = json['languages'];
    return NearbyPersonModel(
      id: id,
      meetingChance: chance,
      isLocked: isLocked,
      photoBytes: photo,
      // Assente (`other`, o un server più vecchio) o sconosciuto: `other`.
      place: _enumOrNull(MeetPlace.values, json['place']) ?? MeetPlace.fallback,
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
    Map<String, Uint8List>? knownPhotos,
  }) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return NearbyPersonModel.fromJson(
        json,
        photos: photos,
        knownPhotos: knownPhotos,
      );
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
