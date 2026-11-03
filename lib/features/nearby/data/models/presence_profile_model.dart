import '/features/profile/domain/entities/profile.dart';
import '/features/session/domain/entities/meet_place.dart';

/// I campi del profilo che partono con la presenza (`{"type": "presence"}`,
/// vedi `server/routes/ws.dart`): solo ciò che serve al server per la
/// sessione in corso. Niente conferma d'età né consenso (restano sul
/// telefono), e il luogo **di questa sessione** (`MeetPlace`; `other` non
/// si manda: il server lo legge come mancante).
///
/// Vive in `nearby/data` (è il formato del protocollo della presenza, non
/// quello dell'archivio del profilo): `nearby` dipende solo dall'entity
/// `Profile`, mai dal `data/` di `profile`.
///
/// **Eccezione voluta** alla regola "il model estende l'entity": è un DTO
/// di sola serializzazione in uscita (una vista ridotta di `Profile` più
/// il luogo della sessione), non la versione JSON di un'entity — non
/// esiste un concetto di dominio "profilo della presenza" da estendere.
class PresenceProfileModel {
  const PresenceProfileModel({
    required this.profile,
    this.place = MeetPlace.fallback,
  });

  final Profile profile;
  final MeetPlace place;

  Map<String, dynamic> toJson() => {
    'gender': profile.gender.name,
    'lookingFor': profile.lookingFor.map((g) => g.name).toList(),
    if (place.isDeclared) 'place': place.name,
    'languages': profile.languages,
    'showGender': profile.showGender,
  };
}
