import 'package:equatable/equatable.dart';

class GeoLocation extends Equatable {
  const GeoLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => [latitude, longitude];
}
