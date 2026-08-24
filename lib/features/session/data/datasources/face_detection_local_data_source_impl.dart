import 'face_detection_local_data_source.dart';
import 'face_detector_stub.dart'
    if (dart.library.io) 'face_detector_io.dart'
    as detector;

/// Implementazione **reale**: usa Google ML Kit, completamente sul
/// dispositivo — nessuna foto lascia il telefono, nessun dato biometrico
/// salvato da nessuna parte. Dice solo "c'è un volto sì/no".
///
/// ML Kit è solo Android/iOS: il pacchetto importa `dart:io`, non
/// compilabile per il web, quindi la vera implementazione (`face_detector_io.dart`)
/// è scambiata a compile-time con un sostituto (`face_detector_stub.dart`)
/// quando `dart:io` non è disponibile — non un semplice `if (kIsWeb)`
/// a runtime, che non basterebbe a far compilare il build web.
class FaceDetectionLocalDataSourceImpl implements FaceDetectionLocalDataSource {
  @override
  Future<bool> detectFace(String imagePath) => detector.detectFace(imagePath);
}
