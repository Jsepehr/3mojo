import '../../domain/entities/profile.dart';

/// Versione di `Profile` che sa scriversi/leggersi in JSON per l'archivio
/// cifrato sul telefono. I campi mandati al server con la presenza sono un
/// altro formato, del protocollo: `PresenceProfileModel` in `nearby/data`.
class ProfileModel extends Profile {
  const ProfileModel({
    required super.gender,
    required super.lookingFor,
    required super.isAdultConfirmed,
    required super.sensitiveDataConsent,
    super.defaultIntent,
    super.languages,
    super.showGender,
    super.acceptedTermsVersion,
  });

  factory ProfileModel.fromEntity(Profile profile) => ProfileModel(
    gender: profile.gender,
    lookingFor: profile.lookingFor,
    isAdultConfirmed: profile.isAdultConfirmed,
    sensitiveDataConsent: profile.sensitiveDataConsent,
    defaultIntent: profile.defaultIntent,
    languages: profile.languages,
    showGender: profile.showGender,
    acceptedTermsVersion: profile.acceptedTermsVersion,
  );

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    final intent = json['defaultIntent'] as String?;
    return ProfileModel(
      gender: Gender.values.byName(json['gender'] as String),
      lookingFor: (json['lookingFor'] as List<dynamic>)
          .map((g) => Gender.values.byName(g as String))
          .toSet(),
      isAdultConfirmed: json['isAdultConfirmed'] as bool,
      sensitiveDataConsent: json['sensitiveDataConsent'] as bool,
      defaultIntent: intent == null ? null : MeetIntent.values.byName(intent),
      languages: (json['languages'] as List<dynamic>).cast<String>(),
      showGender: json['showGender'] as bool,
      // Assente nei profili salvati prima dei termini d'uso: 0, da
      // accettare allo Start.
      acceptedTermsVersion: json['acceptedTermsVersion'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'gender': gender.name,
    'lookingFor': lookingFor.map((g) => g.name).toList(),
    'isAdultConfirmed': isAdultConfirmed,
    'sensitiveDataConsent': sensitiveDataConsent,
    'defaultIntent': defaultIntent?.name,
    'languages': languages,
    'showGender': showGender,
    'acceptedTermsVersion': acceptedTermsVersion,
  };
}
