import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '/features/profile/domain/entities/profile.dart';

/// "Chi sei ora": selfie appena scattato + una copia del profilo (letto dal
/// telefono allo Start) + l'intento scelto per questa sessione. Non è un
/// account — nasce a ogni Start e sparisce a ogni End; il profilo resta sul
/// telefono, il server lo vede solo finché si è online.
/// `sessionId` è generato da zero a ogni Start (mai un id fisso legato al
/// device): serve solo a farsi riconoscere dal server finché si resta
/// online, nella connessione persistente `GET /ws`.
///
/// Il selfie vive **solo in memoria** (`selfieBytes`): il file scritto dalla
/// fotocamera viene cancellato appena letto (`SelfieLocalDataSourceImpl`).
/// Sono questi byte che si mostrano in UI, si controllano (volto) e si
/// mandano al server.
class OnlineSession extends Equatable {
  const OnlineSession({
    required this.sessionId,
    required this.selfieBytes,
    required this.profile,
    this.intent,
  });

  final String sessionId;
  final Uint8List selfieBytes;
  final Profile profile;

  /// Cosa si cerca **stasera**: parte da `Profile.defaultIntent` e si cambia
  /// allo Start; `null` = nessuna icona mostrata agli altri.
  final MeetIntent? intent;

  @override
  List<Object?> get props => [sessionId, selfieBytes, profile, intent];
}
