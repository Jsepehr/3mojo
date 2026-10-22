import 'package:equatable/equatable.dart';

/// Lo sblocco a pagamento visto dal telefono: fino a quando vale
/// ([expiresAt], sull'orologio del telefono) o [UnlockStatus.locked].
///
/// [expiresAt] non viene mai dall'orologio del telefono da solo: è "ora del
/// telefono alla risposta + tempo residuo detto dal server"
/// (`ResolveUnlockExpiryUseCase`), riallineato a ogni controllo. Serve solo
/// a mostrare il tempo che resta: chi vede quali foto lo decide sempre il
/// server.
class UnlockStatus extends Equatable {
  const UnlockStatus.locked() : expiresAt = null;

  const UnlockStatus.until(DateTime this.expiresAt);

  final DateTime? expiresAt;

  @override
  List<Object?> get props => [expiresAt];
}
