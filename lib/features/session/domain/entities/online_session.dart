import 'package:equatable/equatable.dart';

/// Il genere dichiarato dall'utente.
enum Gender { male, female }

/// Il genere che l'utente vuole vedere in "Vicinanze".
enum GenderPreference { male, female, everyone }

/// "Chi sei ora": selfie appena scattato + genere + preferenza. Non è un
/// account — nasce a ogni Start e sparisce a ogni End, nessun dato fisso.
class OnlineSession extends Equatable {
  const OnlineSession({
    required this.selfiePath,
    required this.gender,
    required this.genderPreference,
  });

  final String selfiePath;
  final Gender gender;
  final GenderPreference genderPreference;

  @override
  List<Object?> get props => [selfiePath, gender, genderPreference];
}
