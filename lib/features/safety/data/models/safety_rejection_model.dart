import '../../domain/entities/safety_rejection.dart';

/// Versione di `SafetyRejection` che sa leggersi dal messaggio
/// `{"type": "rejected", "action": "block" | "report", "reason": ...,
/// "personId": ...}` del server.
class SafetyRejectionModel extends SafetyRejection {
  const SafetyRejectionModel({
    required super.action,
    required super.reason,
    super.personId,
  });

  /// `null` se il messaggio non è il rifiuto di un blocco o di una
  /// segnalazione.
  static SafetyRejectionModel? tryFromJson(Map<String, dynamic> json) {
    if (json['type'] != 'rejected') return null;
    final action = switch (json['action']) {
      'block' => SafetyAction.block,
      'report' => SafetyAction.report,
      _ => null,
    };
    if (action == null) return null;

    final reasonName = json['reason'];
    final reason = SafetyRejectionReason.values.firstWhere(
      (value) => value.name == reasonName,
      orElse: () => SafetyRejectionReason.other,
    );
    final personId = json['personId'];
    return SafetyRejectionModel(
      action: action,
      reason: reason,
      personId: personId is String ? personId : null,
    );
  }
}
