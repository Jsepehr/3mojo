import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';

/// Contratto per salvare/leggere conversazioni e messaggi sul dispositivo,
/// e per scambiarli con la controparte in tempo reale.
abstract class ChatLocalDataSource {
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<List<ChatMessageModel>> getMessages(String conversationId);

  /// Salva il messaggio in locale e lo manda a `otherPersonId` sulla
  /// connessione condivisa — nessuna conferma di consegna: se non è online
  /// in questo momento, il messaggio va perso lato server (resta comunque
  /// nella mia cronologia locale).
  Future<ChatMessageModel> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  });

  /// Messaggi in arrivo da `otherPersonId` sulla connessione condivisa —
  /// ognuno viene anche salvato in locale non appena arriva. Apre (o riusa)
  /// la connessione per `sessionId` se non già aperta.
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  });
}
