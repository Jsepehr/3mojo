import 'dart:typed_data';

/// Contratto per scattare il selfie e lavorarlo sul telefono. Il selfie
/// esce di qui **solo come byte in memoria**: nessun file resta su disco.
abstract class SelfieLocalDataSource {
  /// Apre la fotocamera frontale. `null` se l'utente annulla. Il file che
  /// la fotocamera scrive viene letto e cancellato subito.
  Future<Uint8List?> takeSelfie();

  /// Ribalta orizzontalmente il selfie (fotocamere che lo salvano
  /// speculare).
  Future<Uint8List> flipHorizontally(Uint8List selfieBytes);

  /// Cancella eventuali file della fotocamera rimasti su disco (es. un
  /// processo chiuso a metà scatto). Best-effort, non fallisce mai.
  Future<void> discardLeftoverFiles();
}
