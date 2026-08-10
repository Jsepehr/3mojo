import '/features/nearby/domain/entities/nearby_person.dart';

/// Versione di `NearbyPerson` che sa leggersi da JSON — la forma in cui
/// arriverebbe da un vero backend (qui: dal datasource finto).
class NearbyPersonModel extends NearbyPerson {
  const NearbyPersonModel({
    required super.id,
    required super.name,
    required super.photoUrl,
    required super.distanceMeters,
    required super.meetingChancePercent,
  });

  factory NearbyPersonModel.fromJson(Map<String, dynamic> json) {
    return NearbyPersonModel(
      id: json['id'] as String,
      name: json['name'] as String,
      photoUrl: json['photoUrl'] as String,
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      meetingChancePercent: json['meetingChancePercent'] as int,
    );
  }
}
