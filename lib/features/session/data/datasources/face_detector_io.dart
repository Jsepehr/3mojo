import 'package:flutter/services.dart';

/// Canale verso il rilevamento volto **nativo**, tutto sul dispositivo —
/// nessuna foto lascia il telefono:
/// - Android: Google ML Kit (`FaceDetectionChannel.kt`)
/// - iOS: Apple Vision (`AppDelegate.swift`)
///
/// Non si usa il plugin `google_mlkit_face_detection`: i suoi Pod iOS
/// escludono arm64 dal simulatore, quindi bastava averlo tra le dipendenze
/// per non poter più avviare l'app sul simulatore iOS di un Mac Apple Silicon.
///
/// Isolato in un file a parte perché il web non ha questo canale — vedi
/// l'import condizionale in `face_detection_local_data_source_impl.dart`.
const _channel = MethodChannel('raen/face_detection');

Future<bool> detectFace(String imagePath) async {
  final hasFace = await _channel.invokeMethod<bool>('detectFace', {
    'path': imagePath,
  });
  return hasFace ?? false;
}
