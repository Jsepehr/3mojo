import 'package:equatable/equatable.dart';

/// Il genere dichiarato. `unspecified` = "preferisco non dirlo".
enum Gender { male, female, nonBinary, unspecified }

/// Cosa si cerca di solito, mostrato agli altri come icona nella lista
/// "Vicinanze". Lista chiusa apposta: niente testo libero (da moderare, e
/// che collegherebbe le sessioni tra loro).
enum MeetIntent { chat, friendship, meetPeople, openToAnything }

/// Il profilo, compilato una volta e tenuto **solo sul telefono** (cifrato,
/// vedi `ProfileLocalDataSourceImpl`): a ogni Start l'app lo legge e lo
/// manda al server insieme alla presenza, il server lo usa finché si è
/// online e poi lo dimentica. Non è un account: nessun nome, nessun id,
/// niente che sopravviva sul server.
///
/// Agli altri si mostrano solo [defaultIntent] (come intento della
/// sessione), [languages] e — solo se [showGender] — il genere. [lookingFor]
/// non viene **mai** mostrato: serve solo al server per il matching
/// reciproco.
class Profile extends Equatable {
  const Profile({
    required this.gender,
    required this.lookingFor,
    required this.isAdultConfirmed,
    required this.sensitiveDataConsent,
    this.defaultIntent,
    this.languages = const [],
    this.showGender = false,
    this.acceptedTermsVersion = 0,
  });

  /// La versione attuale dei termini d'uso (`CmpTermsOfUse`). Se i termini
  /// cambiano in modo sostanziale si alza di uno: chi aveva accettato la
  /// versione precedente deve accettarli di nuovo (al salvataggio del
  /// profilo e allo Start, vedi `SaveProfileUseCase`/`StartSessionUseCase`).
  static const currentTermsVersion = 1;

  /// I generi che si possono cercare ("Tutti" = tutti e tre).
  static const searchableGenders = {
    Gender.male,
    Gender.female,
    Gender.nonBinary,
  };

  /// Lingue tra cui scegliere (codici ISO 639-1), mostrate come "IT", "EN".
  static const supportedLanguages = [
    'it',
    'en',
    'es',
    'fr',
    'de',
    'pt',
    'ar',
    'zh',
    'ru',
  ];

  static const maxLanguages = 2;

  final Gender gender;
  final Set<Gender> lookingFor;
  final bool isAdultConfirmed;
  final bool sensitiveDataConsent;
  final MeetIntent? defaultIntent;
  final List<String> languages;
  final bool showGender;

  /// Quale versione dei termini d'uso è stata accettata (0 = nessuna: i
  /// profili salvati prima che esistessero). Sta sull'entity perché è una
  /// regola di business a leggerla: senza i termini attuali non si va
  /// online.
  final int acceptedTermsVersion;

  bool get hasAcceptedCurrentTerms =>
      acceptedTermsVersion >= currentTermsVersion;

  bool get looksForEveryone => lookingFor.containsAll(searchableGenders);

  /// Genere + "chi cerchi" lasciano dedurre l'orientamento sessuale (dato
  /// sensibile, art. 9 GDPR): serve il consenso esplicito, tranne nel
  /// percorso neutro — "preferisco non dirlo" e "tutti" — che non rivela
  /// nulla e quindi permette di usare l'app senza dare quel consenso.
  bool get needsSensitiveDataConsent =>
      !(gender == Gender.unspecified && looksForEveryone);

  @override
  List<Object?> get props => [
    gender,
    lookingFor,
    isAdultConfirmed,
    sensitiveDataConsent,
    defaultIntent,
    languages,
    showGender,
    acceptedTermsVersion,
  ];
}
