import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Vero rilevamento volto (Android/iOS): ML Kit sul dispositivo, nessuna
/// foto lascia il telefono. Isolato in un file a parte perché
/// `google_mlkit_face_detection` importa `dart:io`, non compilabile per
/// web — vedi l'import condizionale in `face_detection_local_data_source_impl.dart`.
Future<bool> detectFace(String imagePath) async {
  final detector = FaceDetector(options: FaceDetectorOptions());
  try {
    final faces = await detector.processImage(InputImage.fromFilePath(imagePath));
    return faces.isNotEmpty;
  } finally {
    await detector.close();
  }
}
