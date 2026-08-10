import 'package:equatable/equatable.dart';

enum Gender { male, female }

enum GenderPreference { male, female, everyone }

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
