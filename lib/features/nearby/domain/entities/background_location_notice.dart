import 'package:equatable/equatable.dart';

/// I testi della notifica persistente che Android mostra mentre la
/// posizione viene seguita con l'app in background (foreground service):
/// titolo, testo e nome del canale nelle impostazioni di notifica.
///
/// Sono testi per l'utente, quindi tradotti: li sceglie il livello
/// presentation (dagli ARB) e scendono fino al datasource GPS, che non ha
/// un `BuildContext` (vedi `ProNearby.setBackgroundLocationNotice`).
class BackgroundLocationNotice extends Equatable {
  const BackgroundLocationNotice({
    required this.title,
    required this.body,
    required this.channelName,
  });

  final String title;
  final String body;
  final String channelName;

  @override
  List<Object?> get props => [title, body, channelName];
}
