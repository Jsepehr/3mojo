import 'package:equatable/equatable.dart';

/// Un "benvenuto" del server, a ogni (ri)collegamento della sessione.
///
/// [resumed] = il server aveva ancora la sessione (stessa permanenza,
/// richieste e match); `false` = per il server è una sessione nuova.
/// [isFirstOfSession] = è il primo benvenuto di questa sessione: lì
/// `resumed: false` è normale, dopo una caduta vuol dire che il server ha
/// dimenticato tutto (vedi `WatchServerSessionRestartsUseCase`).
class ServerHandshake extends Equatable {
  const ServerHandshake({
    required this.resumed,
    required this.isFirstOfSession,
  });

  final bool resumed;
  final bool isFirstOfSession;

  @override
  List<Object?> get props => [resumed, isFirstOfSession];
}
