import '../repositories/connection_repository.dart';

/// Azione: l'app torna in primo piano — verifica che il collegamento col
/// server sia ancora vivo. Con l'app in background (soprattutto su iOS, che
/// la sospende) il socket può essere morto senza che nessuno l'abbia chiuso:
/// senza questo controllo si resterebbe "online" su un canale che non porta
/// più nulla finché il sistema operativo non se ne accorge. Se non risponde
/// entro pochi secondi si riconnette subito (vedi
/// `RealtimeConnection.checkAlive`).
class CheckConnectionUseCase {
  const CheckConnectionUseCase(this._repository);

  final ConnectionRepository _repository;

  void call() => _repository.checkConnection();
}
