import 'dart:typed_data';

import 'face_detection_local_data_source.dart';

/// Implementazione **finta** del controllo del volto, per la demo
/// dichiarata (`DemoScope`): il "selfie" della demo è un'illustrazione
/// (`SelfieLocalDataSourceFakeImpl`), senza un volto vero da cercare.
/// Nessun canale nativo chiamato: dice sempre di sì.
class FaceDetectionLocalDataSourceFakeImpl
    implements FaceDetectionLocalDataSource {
  @override
  Future<bool> detectFace(Uint8List imageBytes) async => true;
}
