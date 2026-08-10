import '../../domain/entities/encounter_request.dart';

class EncounterRequestModel extends EncounterRequest {
  const EncounterRequestModel({
    required super.id,
    required super.otherPersonId,
    required super.otherSelfiePath,
    required super.status,
  });

  factory EncounterRequestModel.fromEntity(EncounterRequest request) {
    return EncounterRequestModel(
      id: request.id,
      otherPersonId: request.otherPersonId,
      otherSelfiePath: request.otherSelfiePath,
      status: request.status,
    );
  }

  @override
  EncounterRequestModel copyWith({EncounterRequestStatus? status}) {
    return EncounterRequestModel(
      id: id,
      otherPersonId: otherPersonId,
      otherSelfiePath: otherSelfiePath,
      status: status ?? this.status,
    );
  }
}
