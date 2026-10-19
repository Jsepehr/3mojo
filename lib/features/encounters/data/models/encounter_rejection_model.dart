import '../../domain/entities/encounter_rejection.dart';

/// Versione di `EncounterRejection` che sa leggersi dal messaggio
/// `{"type": "rejected", "action": ..., "reason": ..., ...}` del server.
class EncounterRejectionModel extends EncounterRejection {
  const EncounterRejectionModel({
    required super.action,
    required super.reason,
    super.otherPersonId,
    super.requestId,
  });

  /// `null` se il messaggio non è un rifiuto di un'azione sulle richieste
  /// d'incontro (es. un rifiuto della presenza o della chat).
  static EncounterRejectionModel? tryFromJson(Map<String, dynamic> json) {
    if (json['type'] != 'rejected') return null;
    final action = switch (json['action']) {
      'sendEncounterRequest' => EncounterAction.sendRequest,
      'respondToEncounterRequest' => EncounterAction.respondToRequest,
      _ => null,
    };
    if (action == null) return null;

    final reasonName = json['reason'];
    final reason = EncounterRejectionReason.values.firstWhere(
      (value) => value.name == reasonName,
      orElse: () => EncounterRejectionReason.other,
    );
    final otherPersonId = json['toPersonId'];
    final requestId = json['requestId'];
    return EncounterRejectionModel(
      action: action,
      reason: reason,
      otherPersonId: otherPersonId is String ? otherPersonId : null,
      requestId: requestId is String ? requestId : null,
    );
  }
}
