import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';

/// Contratto per tenere conversazioni e messaggi **solo in memoria** (mai su
/// disco: finita l'app o il match non ne resta traccia sul telefono), e per
/// scambiarli con la controparte in tempo reale.
abstract class ChatLocalDataSource {
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    required String otherSelfiePath,
  });

  Future<List<ChatMessageModel>> getMessages(String conversationId);

  /// Aggiunge il messaggio alla cronologia in memoria e lo manda a
  /// `otherPersonId` sulla connessione condivisa — nessuna conferma di
  /// consegna: se non è online in questo momento, il messaggio va perso lato
  /// server (resta comunque nella mia cronologia finché dura il match).
  Future<ChatMessageModel> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  });

  /// Messaggi in arrivo da `otherPersonId` sulla connessione condivisa —
  /// ognuno viene anche aggiunto alla cronologia in memoria non appena
  /// arriva. Apre (o riusa)
  /// la connessione per `sessionId` se non già aperta.
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  });

  /// Cancella la conversazione con `otherPersonId` e tutta la sua
  /// cronologia — chiamato quando il match finisce, così la chat
  /// non sopravvive alla fine dell'incontro.
  Future<void> deleteConversation(String otherPersonId);
}
