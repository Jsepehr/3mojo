/// Il profilo che il client manda con la presenza (genere, chi cerca,
/// intento, lingue, "mostra il mio genere") — validato qui, mai fidato così
/// com'è: valori fuori dalle liste chiuse diventano neutri invece di finire
/// nei payload verso gli altri utenti.
///
/// Vive solo in RAM e solo finché la sessione è online, come tutto il resto:
/// il profilo vero resta sul telefono dell'utente.
class PresenceProfile {
  const PresenceProfile({
    this.gender = unspecified,
    this.lookingFor = searchableGenders,
    this.intent,
    this.languages = const [],
    this.showGender = false,
  });

  /// Profilo di chi non ha detto nulla: "preferisco non dirlo", cerca tutti.
  static const anonymous = PresenceProfile();

  static const unspecified = 'unspecified';
  static const searchableGenders = {'male', 'female', 'nonBinary'};
  static const genders = {...searchableGenders, unspecified};
  static const intents = {'chat', 'friendship', 'meetPeople', 'openToAnything'};
  static const maxLanguages = 2;

  /// Lista chiusa delle lingue accettate: **la stessa** di
  /// `Profile.supportedLanguages` nel client
  /// (`lib/features/profile/domain/entities/profile.dart`) — se cambia una,
  /// va cambiata anche l'altra. Un codice qualsiasi di due lettere non basta:
  /// lingue rare o inventate diventerebbero un'etichetta quasi univoca, utile
  /// a riconoscere la stessa persona tra una sessione e l'altra.
  static const supportedLanguages = {
    'it',
    'en',
    'es',
    'fr',
    'de',
    'pt',
    'ar',
    'zh',
    'ru',
  };

  final String gender;
  final Set<String> lookingFor;
  final String? intent;
  final List<String> languages;
  final bool showGender;

  factory PresenceProfile.fromJson(Map<String, dynamic> json) {
    final rawGender = json['gender'];
    final gender = genders.contains(rawGender)
        ? rawGender as String
        : unspecified;

    final rawLookingFor = json['lookingFor'];
    final lookingFor = rawLookingFor is List
        ? rawLookingFor
              .whereType<String>()
              .where(searchableGenders.contains)
              .toSet()
        : <String>{};

    final rawIntent = json['intent'];
    final rawLanguages = json['languages'];

    return PresenceProfile(
      gender: gender,
      // Vuoto o assente: nessuna preferenza dichiarata, quindi "tutti".
      lookingFor: lookingFor.isEmpty ? searchableGenders : lookingFor,
      intent: intents.contains(rawIntent) ? rawIntent as String : null,
      languages: rawLanguages is List
          ? rawLanguages
                .whereType<String>()
                .where(supportedLanguages.contains)
                .toSet()
                .take(maxLanguages)
                .toList()
          : const [],
      showGender: json['showGender'] == true && gender != unspecified,
    );
  }

  /// Chi ha questo profilo vuole vedere qualcuno di genere [otherGender]?
  /// Chi ha scelto "preferisco non dirlo" è visibile solo a chi cerca tutti:
  /// non si può dire che rientri in una preferenza più ristretta.
  bool accepts(String otherGender) => otherGender == unspecified
      ? lookingFor.containsAll(searchableGenders)
      : lookingFor.contains(otherGender);

  /// Matching **reciproco**: due persone si vedono solo se ognuna rientra in
  /// ciò che cerca l'altra. Con un filtro a senso unico chi cerca solo donne
  /// riceverebbe comunque richieste da chi non le interessa — e qui ci si
  /// incontra di persona, entro 100 metri.
  static bool mutuallyCompatible(PresenceProfile a, PresenceProfile b) =>
      a.accepts(b.gender) && b.accepts(a.gender);

  /// Il genere da mostrare agli altri: solo se la persona l'ha scelto.
  String? get visibleGender => showGender ? gender : null;
}
