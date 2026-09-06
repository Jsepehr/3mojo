/// Contratto per l'identificatore anonimo del dispositivo usato dal
/// paywall — mai un nome/email/profilo, solo un ID casuale che permette al
/// server di ricordare "questo dispositivo ha già sbloccato" tra un
/// controllo e l'altro.
abstract class PaywallLocalDataSource {
  /// Lo crea al primo utilizzo e lo persiste per sempre (a differenza del
  /// `sessionId` di `session/`, che è usa-e-getta e cambia a ogni Start):
  /// uno sblocco pagato deve restare riconoscibile anche dopo aver
  /// chiuso/riaperto l'app, o End/Start più volte.
  Future<String> getOrCreateDeviceId();
}
