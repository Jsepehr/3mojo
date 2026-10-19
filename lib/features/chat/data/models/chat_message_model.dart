import '../../domain/entities/chat_message.dart';

/// Versione di `ChatMessage` del layer `data/`. Nessun JSON: la cronologia
/// vive solo in memoria (vedi `ChatRemoteDataSourceImpl`), mai su disco; i
/// messaggi in rete hanno il loro formato (`{"type": "chatMessage", ...}`),
/// letto e scritto direttamente dal datasource.
class ChatMessageModel extends ChatMessage {
  const ChatMessageModel({
    required super.id,
    required super.isMine,
    required super.text,
    required super.sentAt,
  });
}
