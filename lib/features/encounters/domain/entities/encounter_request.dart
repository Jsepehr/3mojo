import 'package:equatable/equatable.dart';

enum EncounterRequestStatus { pending, accepted, declined, cancelled, ended }

class EncounterRequest extends Equatable {
  const EncounterRequest({
    required this.id,
    required this.otherPersonId,
    required this.otherSelfiePath,
    required this.status,
  });

  final String id;
  final String otherPersonId;
  final String otherSelfiePath;
  final EncounterRequestStatus status;

  EncounterRequest copyWith({EncounterRequestStatus? status}) {
    return EncounterRequest(
      id: id,
      otherPersonId: otherPersonId,
      otherSelfiePath: otherSelfiePath,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [id, otherPersonId, otherSelfiePath, status];
}
