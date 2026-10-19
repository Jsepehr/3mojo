import 'package:threemojo_app/features/chat/domain/usecases/delete_conversation_usecase.dart';
import 'package:threemojo_app/features/chat/domain/usecases/get_messages_usecase.dart';
import 'package:threemojo_app/features/chat/domain/usecases/get_or_create_conversation_usecase.dart';
import 'package:threemojo_app/features/chat/domain/usecases/send_message_usecase.dart';
import 'package:threemojo_app/features/chat/domain/usecases/start_receiving_chat_messages_usecase.dart';
import 'package:threemojo_app/features/chat/domain/usecases/watch_incoming_chat_messages_usecase.dart';
import 'package:threemojo_app/features/chat/domain/usecases/watch_undelivered_chat_messages_usecase.dart';
import 'package:threemojo_app/features/chat/presentation/providers/pro_chat.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/detect_ended_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/end_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/forget_ended_match_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/respond_to_encounter_request_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/send_encounter_request_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/watch_encounter_rejections_usecase.dart';
import 'package:threemojo_app/features/encounters/domain/usecases/watch_encounter_requests_usecase.dart';
import 'package:threemojo_app/features/encounters/presentation/providers/pro_encounters.dart';
import 'package:threemojo_app/features/session/domain/usecases/get_current_session_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_server_session_restarts_usecase.dart';
import 'package:threemojo_app/features/session/domain/usecases/watch_session_usecase.dart';

import 'fake_repositories.dart';

ProEncounters buildProEncounters({
  required FakeSessionRepository sessions,
  required FakeEncounterRepository encounters,
  required FakeChatRepository chat,
  FakeConnectionRepository? connection,
  DateTime Function()? now,
}) => ProEncounters(
  watchSessionUseCase: WatchSessionUseCase(sessions),
  watchServerSessionRestartsUseCase: WatchServerSessionRestartsUseCase(
    connection ?? FakeConnectionRepository(),
  ),
  watchEncounterRequestsUseCase: WatchEncounterRequestsUseCase(
    getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
    repository: encounters,
  ),
  watchEncounterRejectionsUseCase: WatchEncounterRejectionsUseCase(
    getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
    repository: encounters,
  ),
  sendEncounterRequestUseCase: SendEncounterRequestUseCase(encounters),
  respondToEncounterRequestUseCase: RespondToEncounterRequestUseCase(
    encounters,
  ),
  endMatchUseCase: EndMatchUseCase(encounters, DeleteConversationUseCase(chat)),
  detectEndedMatchUseCase: DetectEndedMatchUseCase(
    ForgetEndedMatchUseCase(DeleteConversationUseCase(chat)),
  ),
  now: now,
);

ProChat buildProChat({
  required FakeSessionRepository sessions,
  required FakeChatRepository chat,
}) => ProChat(
  watchSessionUseCase: WatchSessionUseCase(sessions),
  getOrCreateConversationUseCase: GetOrCreateConversationUseCase(chat),
  getMessagesUseCase: GetMessagesUseCase(chat),
  sendMessageUseCase: SendMessageUseCase(chat),
  startReceivingChatMessagesUseCase: StartReceivingChatMessagesUseCase(chat),
  watchIncomingChatMessagesUseCase: WatchIncomingChatMessagesUseCase(
    getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
    repository: chat,
  ),
  watchUndeliveredChatMessagesUseCase: WatchUndeliveredChatMessagesUseCase(
    getCurrentSessionUseCase: GetCurrentSessionUseCase(sessions),
    repository: chat,
  ),
);
