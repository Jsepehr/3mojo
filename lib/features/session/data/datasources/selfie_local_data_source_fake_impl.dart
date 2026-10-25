import 'dart:typed_data';

import '/core/utils/illustrated_avatar.dart';
import 'selfie_local_data_source.dart';

/// Implementazione **finta** del selfie, per la demo dichiarata
/// (`DemoScope`): nessuna fotocamera, nessun permesso, nessun file. Lo
/// "scatto" è un avatar illustrato generato sul telefono
/// (`illustratedAvatarPng`), che resta in memoria e non esce mai di qui —
/// nella demo non c'è nessun server a cui mandarlo.
class SelfieLocalDataSourceFakeImpl implements SelfieLocalDataSource {
  /// Il seed dell'avatar del "proprio selfie" della demo: un colore diverso
  /// da quelli delle persone dimostrative.
  static const int ownAvatarSeed = 0;

  @override
  Future<Uint8List?> takeSelfie() async => illustratedAvatarPng(ownAvatarSeed);

  /// Un'illustrazione simmetrica: ribaltata è uguale.
  @override
  Future<Uint8List> flipHorizontally(Uint8List selfieBytes) async =>
      selfieBytes;

  @override
  Future<void> discardLeftoverFiles() async {}
}
