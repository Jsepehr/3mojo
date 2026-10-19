import '/features/profile/domain/entities/profile.dart';

/// I campi del profilo che partono con la presenza (`{"type": "presence"}`,
/// vedi `server/routes/ws.dart`): solo ciò che serve al server per la
/// sessione in corso. Niente conferma d'età né consenso (restano sul
/// telefono), e l'intento **di questa sessione** al posto di quello
/// predefinito.
///
/// Vive in `nearby/data` (è il formato del protocollo della presenza, non
/// quello dell'archivio del profilo): `nearby` dipende solo dall'entity
/// `Profile`, mai dal `data/` di `profile`.
///
/// **Eccezione voluta** alla regola "il model estende l'entity": è un DTO
/// di sola serializzazione in uscita (una vista ridotta di `Profile` più
/// l'intento della sessione), non la versione JSON di un'entity — non
/// esiste un concetto di dominio "profilo della presenza" da estendere.
class PresenceProfileModel {
  const PresenceProfileModel({required this.profile, this.intent});

  final Profile profile;
  final MeetIntent? intent;

  Map<String, dynamic> toJson() => {
    'gender': profile.gender.name,
    'lookingFor': profile.lookingFor.map((g) => g.name).toList(),
    if (intent != null) 'intent': intent!.name,
    'languages': profile.languages,
    'showGender': profile.showGender,
  };
}
