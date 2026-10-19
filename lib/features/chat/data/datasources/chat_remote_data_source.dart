import 'dart:typed_data';

import '../models/chat_message_model.dart';
import '../models/conversation_model.dart';

/// Contratto per scambiare messaggi con la controparte in tempo reale
/// (via rete: per questo "remote") e tenere conversazioni e messaggi **solo
/// in memoria** (mai su disco: finita l'app, la sessione o il match non ne
/// resta traccia sul telefono, e il server non conserva nulla).
abstract class ChatRemoteDataSource {
  Future<ConversationModel> getOrCreateConversation({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  });

  Future<List<ChatMessageModel>> getMessages(String conversationId);

  /// Manda il messaggio a `otherPersonId` sulla connessione condivisa e,
  /// **solo se è partito**, lo aggiunge alla cronologia in memoria. Lancia
  /// `ServerException` se la connessione non è pronta (offline, in
  /// riconnessione): il messaggio non va considerato inviato. Nessuna
  /// conferma di consegna: il server può ancora scartarlo (destinatario
  /// offline) e in quel caso risponde `rejected` con `clientMessageId` =
  /// l'id del messaggio.
  Future<ChatMessageModel> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  });

  /// Apre (se non già aperto) l'unico ascolto della connessione per
  /// `sessionId`: da qui in poi ogni messaggio in arrivo finisce nella
  /// cronologia in memoria, **anche se la pagina del match non è ancora
  /// aperta** (il partner può scrivere un istante dopo il match, prima che
  /// la pagina si apra). Da chiamare all'inizio della sessione.
  void startReceiving(String sessionId);

  /// Messaggi in arrivo da `otherPersonId`. Un solo ascolto della
  /// connessione per tutta la sessione (aperto da [startReceiving] o alla
  /// prima chiamata per `sessionId`) li riceve e li aggiunge alla
  /// cronologia **una volta**, qualunque sia il numero di chi ascolta;
  /// cambiare sessione svuota tutto.
  Stream<ChatMessageModel> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  });

  /// Cancella la conversazione con `otherPersonId` e tutta la sua
  /// cronologia — chiamato quando il match finisce: la chat non sopravvive
  /// alla fine dell'incontro, e quello che arrivasse ancora da quella
  /// persona in questa sessione viene scartato.
  Future<void> deleteConversation(String otherPersonId);

  /// Gli id ([ChatMessageModel.id], mandato come `clientMessageId`) dei
  /// messaggi che il server ha rifiutato (`rejected`): non sono arrivati.
  Stream<String> watchUndeliveredMessageIds({required String sessionId});

  /// Dimentica tutte le conversazioni e la cronologia (End).
  Future<void> reset();
}
