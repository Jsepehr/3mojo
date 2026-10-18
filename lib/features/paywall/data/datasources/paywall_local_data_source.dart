/// Contratto per il token di sblocco a pagamento sul telefono — mai un
/// identificativo del dispositivo: esiste solo dopo un acquisto e solo
/// finché vale (2 ore), chi non paga non ne ha nessuno.
abstract class PaywallLocalDataSource {
  /// Il token salvato, o `null` se non c'è (mai pagato, o già scaduto).
  Future<String?> readUnlockToken();

  /// Salva il token appena emesso dal server, valido per [validFor].
  Future<void> saveUnlockToken(String token, Duration validFor);

  /// Dimentica il token (es. il server dice che non vale più).
  Future<void> clearUnlockToken();
}
