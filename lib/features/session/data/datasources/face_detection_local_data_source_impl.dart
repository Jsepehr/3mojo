import 'face_detection_local_data_source.dart';
import 'face_detector_stub.dart'
    if (dart.library.io) 'face_detector_io.dart'
    as detector;

/// Implementazione **reale**: rilevamento nativo (ML Kit su Android, Apple
/// Vision su iOS), completamente sul dispositivo — nessuna foto lascia il
/// telefono, nessun dato biometrico salvato da nessuna parte. Dice solo
/// "c'è un volto sì/no".
///
/// Il canale nativo esiste solo su Android/iOS, quindi sul web la vera
/// implementazione (`face_detector_io.dart`) è scambiata a compile-time con
/// un sostituto (`face_detector_stub.dart`) quando `dart:io` non è
/// disponibile — altrimenti nel browser la chiamata al canale fallirebbe
/// sempre e bloccherebbe lo Start.
class FaceDetectionLocalDataSourceImpl implements FaceDetectionLocalDataSource {
  @override
  Future<bool> detectFace(String imagePath) => detector.detectFace(imagePath);
}
