import '../../domain/entities/conversation.dart';

/// Versione di `Conversation` con `fromJson`/`toJson`, stessa ragione di
/// `ChatMessageModel`.
class ConversationModel extends Conversation {
  const ConversationModel({
    required super.id,
    required super.otherPersonId,
    required super.otherSelfiePath,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      otherPersonId: json['otherPersonId'] as String,
      otherSelfiePath: json['otherSelfiePath'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'otherPersonId': otherPersonId,
      'otherSelfiePath': otherSelfiePath,
    };
  }
}
