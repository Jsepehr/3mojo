import '../../domain/entities/conversation.dart';

/// Versione di `Conversation` del layer `data/`. Nessun JSON: la
/// conversazione vive solo in memoria (vedi `ChatRemoteDataSourceImpl`) e
/// non viaggia mai in rete né su disco.
class ConversationModel extends Conversation {
  const ConversationModel({
    required super.id,
    required super.otherPersonId,
    super.otherSelfieBytes,
  });
}
