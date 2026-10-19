import 'dart:typed_data';

/// Sostituto per il web: il canale nativo non esiste nel browser, quindi non c'è modo di
/// eseguire davvero il controllo — si assume "c'è un volto" per non
/// bloccare i test da browser. Resta comunque obbligatorio scattare o
/// caricare un selfie, si salta solo la verifica del contenuto.
Future<bool> detectFace(
  Uint8List imageBytes, {
  Future<bool> Function(String path)? detectAtPath,
}) async => true;
