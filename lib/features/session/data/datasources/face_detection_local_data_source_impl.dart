import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_detection_local_data_source.dart';

/// Implementazione **reale**: usa Google ML Kit, completamente sul
/// dispositivo — nessuna foto lascia il telefono, nessun dato biometrico
/// salvato da nessuna parte. Dice solo "c'è un volto sì/no".
class FaceDetectionLocalDataSourceImpl implements FaceDetectionLocalDataSource {
  @override
  Future<bool> detectFace(String imagePath) async {
    final detector = FaceDetector(options: FaceDetectorOptions());
    try {
      final faces = await detector.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return faces.isNotEmpty;
    } finally {
      await detector.close();
    }
  }
}
