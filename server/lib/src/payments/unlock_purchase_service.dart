import 'dart:async';

import '../paywall_store.dart';
import 'receipt_verifier.dart';
import 'redeemed_transactions.dart';

/// Uno sblocco emesso per un acquisto verificato.
class UnlockGrant {
  const UnlockGrant({
    required this.unlockToken,
    required this.remaining,
    required this.replayed,
  });

  final String unlockToken;
  final Duration remaining;

  /// `true` se la stessa transazione era già stata riscattata e il token è
  /// quello di allora (nuovo tentativo dopo una risposta persa).
  final bool replayed;
}

/// La transazione è già stata riscattata e il suo sblocco non vale più (o
/// Google la dà già per consumata senza che sia nel registro): 409.
class PurchaseAlreadyRedeemedException implements Exception {
  const PurchaseAlreadyRedeemedException();
}

/// La piattaforma non è accettata dal server in questa modalità (es. `fake`
/// con `PAYMENTS_MODE=real`, o `ios` senza configurazione Apple): 503.
class PlatformNotEnabledException implements Exception {
  const PlatformNotEnabledException(this.platform);

  final StorePlatform platform;
}

/// Trasforma un acquisto **verificato** in uno sblocco di 2 ore
/// (`PaywallStore`), una volta sola per transazione.
///
/// Ordine, pensato perché un pagamento non vada mai perso né valga due
/// volte:
/// 1. la piattaforma è abilitata e il prodotto dichiarato è quello
///    configurato;
/// 2. il negozio conferma l'acquisto ([ReceiptVerifier.verify]) e il
///    prodotto **firmato** è quello configurato;
/// 3. registro ([RedeemedTransactions]): già riscattata → stesso token se
///    vale ancora, altrimenti 409;
/// 4. senza protezione del negozio contro il riuso (Apple), la transazione
///    deve essere più giovane di [maxPurchaseAge];
/// 5. token emesso e registrato, **poi** il negozio chiude l'acquisto
///    ([ReceiptVerifier.finalize], Google `consume`): se questo fallisce il
///    token è revocato e il registro annullato — l'app non ha completato
///    l'acquisto e riproverà.
///
/// Due richieste contemporanee per la stessa transazione aspettano lo
/// stesso esito.
class UnlockPurchaseService {
  UnlockPurchaseService({
    required Map<StorePlatform, ReceiptVerifier> verifiers,
    required Map<StorePlatform, String> productIds,
    required RedeemedTransactions registry,
    required PaywallStore paywallStore,
    DateTime Function()? now,
    this.maxPurchaseAge = const Duration(days: 7),
  }) : _verifiers = verifiers,
       _productIds = productIds,
       _registry = registry,
       _paywallStore = paywallStore,
       _now = now ?? DateTime.now {
    assert(
      registry.retention > maxPurchaseAge,
      'il registro deve ricordare più a lungo di quanto un acquisto resta '
      'riscattabile',
    );
  }

  final Map<StorePlatform, ReceiptVerifier> _verifiers;
  final Map<StorePlatform, String> _productIds;
  final RedeemedTransactions _registry;
  final PaywallStore _paywallStore;
  final DateTime Function() _now;

  /// Oltre questa età un acquisto Apple non si riscatta più (dopo, una
  /// transazione uscita dal registro potrebbe essere riscattata di nuovo).
  /// Una settimana copre l'app rimasta chiusa o senza rete per giorni
  /// dopo aver pagato.
  final Duration maxPurchaseAge;

  final Map<String, Future<UnlockGrant>> _inFlightByClaim = {};
  final Map<String, Future<UnlockGrant>> _inFlightByTransaction = {};

  /// Lancia [PlatformNotEnabledException], [ReceiptRejectedException],
  /// [PurchaseAlreadyRedeemedException], [StoreNotConfiguredException] o
  /// [StoreUnavailableException].
  Future<UnlockGrant> redeem(PurchaseClaim claim) {
    final verifier = _verifiers[claim.platform];
    final productId = _productIds[claim.platform];
    if (verifier == null || productId == null) {
      return Future.error(PlatformNotEnabledException(claim.platform));
    }
    if (claim.productId != productId) {
      return Future.error(
        const ReceiptRejectedException(ReceiptRejection.wrongProduct),
      );
    }
    final key = '${claim.platform.name}:${claim.receipt}';
    final existing = _inFlightByClaim[key];
    if (existing != null) return existing;
    final future = _redeem(claim, verifier, productId);
    _inFlightByClaim[key] = future;
    return future.whenComplete(() {
      _inFlightByClaim.remove(key);
    });
  }

  Future<UnlockGrant> _redeem(
    PurchaseClaim claim,
    ReceiptVerifier verifier,
    String productId,
  ) async {
    final verified = await verifier.verify(claim);
    if (verified.productId != productId) {
      throw const ReceiptRejectedException(ReceiptRejection.wrongProduct);
    }
    final hash = await _registry.hash(
      verified.platform,
      verified.transactionKey,
    );

    final inProgress = _inFlightByTransaction[hash];
    if (inProgress != null) {
      try {
        final grant = await inProgress;
        return UnlockGrant(
          unlockToken: grant.unlockToken,
          remaining: grant.remaining,
          replayed: true,
        );
      } catch (_) {
        // L'altro tentativo è fallito: si prova da capo qui sotto.
      }
    }

    final redeemed = _registry.lookup(hash);
    if (redeemed != null) {
      final token = redeemed.unlockToken;
      final remaining = token == null
          ? null
          : _paywallStore.remainingFor(token);
      if (token != null && remaining != null) {
        return UnlockGrant(
          unlockToken: token,
          remaining: remaining,
          replayed: true,
        );
      }
      _registry.forgetToken(hash);
      throw const PurchaseAlreadyRedeemedException();
    }
    if (verified.alreadyConsumed) {
      throw const PurchaseAlreadyRedeemedException();
    }
    if (!verified.storeEnforcesSingleUse &&
        _now().difference(verified.purchasedAt) > maxPurchaseAge) {
      throw const ReceiptRejectedException(ReceiptRejection.tooOld);
    }

    final completer = Completer<UnlockGrant>();
    // Nessuno aspetta per forza questo future: un errore non deve finire
    // tra quelli "non gestiti".
    completer.future.ignore();
    _inFlightByTransaction[hash] = completer.future;
    try {
      final token = _paywallStore.issueUnlockToken();
      _registry.record(hash, token);
      try {
        await verifier.finalize(verified);
      } catch (_) {
        _registry.remove(hash);
        _paywallStore.revoke(token);
        rethrow;
      }
      final grant = UnlockGrant(
        unlockToken: token,
        remaining:
            _paywallStore.remainingFor(token) ?? PaywallStore.unlockDuration,
        replayed: false,
      );
      completer.complete(grant);
      return grant;
    } catch (e, stack) {
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _inFlightByTransaction.remove(hash);
    }
  }

  /// Revoca lo sblocco nato dalla transazione (rimborso / revoca notificati
  /// dal negozio). `true` se c'era un token ancora valido.
  Future<bool> revokeTransaction(
    StorePlatform platform,
    String transactionKey,
  ) async {
    final hash = await _registry.hash(platform, transactionKey);
    final token = _registry.forgetToken(hash);
    // Anche se non era ancora stata riscattata: dopo un rimborso non deve
    // più poterlo essere.
    _registry.markRedeemed(hash);
    return token != null && _paywallStore.revoke(token);
  }
}
