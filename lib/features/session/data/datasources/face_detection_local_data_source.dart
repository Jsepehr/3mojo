/// Contratto per verificare, sul dispositivo, se una foto contiene un volto.
abstract class FaceDetectionLocalDataSource {
  Future<bool> detectFace(String imagePath);
}
