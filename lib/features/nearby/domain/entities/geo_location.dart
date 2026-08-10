import 'package:equatable/equatable.dart';

/// Una coppia lat/lng: la posizione GPS del proprio telefono in questo
/// istante. Nome scelto per non confliggere con `Position` di geolocator.
class GeoLocation extends Equatable {
  const GeoLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => [latitude, longitude];
}
