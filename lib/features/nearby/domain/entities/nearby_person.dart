import 'package:equatable/equatable.dart';

/// Una persona vista nella lista "Vicinanze": chi è, quanto è distante, e
/// quanto è probabile incontrarla (in base a quanto è rimasta ferma lì).
class NearbyPerson extends Equatable {
  const NearbyPerson({
    required this.id,
    required this.name,
    required this.photoUrl,
    required this.distanceMeters,
    required this.meetingChancePercent,
  });

  final String id;
  final String name;
  final String photoUrl;
  final double distanceMeters;

  /// Rises 0→100 over 5 minutes stationary, resets on exit; hidden below 1 minute; computed server-side.
  final int meetingChancePercent;

  @override
  List<Object?> get props => [
    id,
    name,
    photoUrl,
    distanceMeters,
    meetingChancePercent,
  ];
}
