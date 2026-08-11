import 'package:equatable/equatable.dart';

/// I tre stadi (e soli tre) della probabilità d'incontro: `low` da 1 minuto
/// di permanenza, `medium` da 3, `high` da 5 — calcolato lato server dalla
/// storia di posizione della persona, il client riceve solo il valore già
/// pronto (nessun numero, nessuna via di mezzo continua).
enum MeetingChance { low, medium, high }

/// Una persona vista nella lista "Vicinanze": niente nome (l'app non lo
/// chiede mai), solo una foto, quanto è distante, e quanto è probabile
/// incontrarla (in base a quanto è rimasta ferma lì).
class NearbyPerson extends Equatable {
  const NearbyPerson({
    required this.id,
    required this.photoUrl,
    required this.distanceMeters,
    required this.meetingChance,
  });

  final String id;
  final String photoUrl;
  final double distanceMeters;
  final MeetingChance meetingChance;

  @override
  List<Object?> get props => [id, photoUrl, distanceMeters, meetingChance];
}
