import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/chat_message.dart';
import '../entities/conversation.dart';

/// Contratto per aprire una conversazione e scambiare messaggi in tempo
/// reale con la controparte. [appendMessage] ritorna `Left(ConnectionFailure)`
/// se il messaggio non è potuto partire (offline, in riconnessione): in quel
/// caso non finisce nella cronologia.
abstract class ChatRepository {
  Future<Either<Failure, Conversation>> getOrCreateConversation({
    required String otherPersonId,
    Uint8List? otherSelfieBytes,
  });

  Future<Either<Failure, List<ChatMessage>>> getMessages(String conversationId);

  Future<Either<Failure, ChatMessage>> appendMessage({
    required String conversationId,
    required String otherPersonId,
    required String text,
  });

  /// Inizia a ricevere (e tenere in memoria) i messaggi della sessione
  /// [sessionId], prima ancora che una conversazione sia aperta.
  Either<Failure, Unit> startReceivingMessages({required String sessionId});

  Stream<Either<Failure, ChatMessage>> watchIncomingMessages({
    required String sessionId,
    required String otherPersonId,
  });

  Future<Either<Failure, void>> deleteConversation(String otherPersonId);

  /// Gli id dei messaggi miei che il server ha scartato (destinatario non
  /// più raggiungibile, testo non valido): non sono arrivati. Non fallisce:
  /// i problemi di connessione arrivano già da [watchIncomingMessages].
  Stream<String> watchUndeliveredMessageIds({required String sessionId});

  /// Dimentica tutte le conversazioni della sessione appena finita (End).
  Future<Either<Failure, Unit>> clearSessionState();
}
