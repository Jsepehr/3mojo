import '../entities/unlock_status.dart';

/// Azione: dal tempo residuo detto dal server alla scadenza sul telefono —
/// `ora del telefono adesso + residuo`, calcolata **appena arriva la
/// risposta**. Così conta solo quanto manca per il server: un orologio del
/// telefono avanti o indietro di ore non sposta la fine dello sblocco
/// (sposterebbe solo l'ora "fino alle…" mostrata, coerente con l'orologio
/// che la persona vede). Un residuo nullo o negativo = bloccato.
///
/// Sotto-passo comune di `GetUnlockStatusUseCase` e `PurchaseUnlockUseCase`.
class ResolveUnlockExpiryUseCase {
  ResolveUnlockExpiryUseCase({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  UnlockStatus call(Duration remaining) => remaining > Duration.zero
      ? UnlockStatus.until(_now().add(remaining))
      : const UnlockStatus.locked();
}
