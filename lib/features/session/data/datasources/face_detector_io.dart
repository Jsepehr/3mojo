import 'dart:io';

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

Future<bool> _detectAtPath(String path) async {
  final hasFace = await _channel.invokeMethod<bool>('detectFace', {
    'path': path,
  });
  return hasFace ?? false;
}

/// Il canale nativo vuole un percorso (così ML Kit/Vision leggono anche
/// l'orientamento EXIF): i byte vengono scritti in un file temporaneo in
/// una cartella creata apposta, che viene cancellata **sempre** alla fine
/// del controllo — anche se il canale fallisce. [detectAtPath] serve ai
/// test, al posto del canale vero.
Future<bool> detectFace(
  Uint8List imageBytes, {
  Future<bool> Function(String path)? detectAtPath,
}) async {
  final directory = await Directory.systemTemp.createTemp('raen_face_check_');
  try {
    final file = File('${directory.path}${Platform.pathSeparator}selfie.jpg');
    await file.writeAsBytes(imageBytes, flush: true);
    return await (detectAtPath ?? _detectAtPath)(file.path);
  } finally {
    try {
      await directory.delete(recursive: true);
    } catch (_) {
      // Già sparita: niente da fare.
    }
  }
}
