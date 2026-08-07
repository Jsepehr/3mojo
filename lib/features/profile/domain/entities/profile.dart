import 'package:equatable/equatable.dart';

class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.name,
    required this.age,
    required this.bio,
    required this.photoUrl,
  });

  final String id;
  final String name;
  final int age;
  final String bio;
  final String photoUrl;

  Profile copyWith({String? name, int? age, String? bio, String? photoUrl}) {
    return Profile(
      id: id,
      name: name ?? this.name,
      age: age ?? this.age,
      bio: bio ?? this.bio,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  @override
  List<Object?> get props => [id, name, age, bio, photoUrl];
}
