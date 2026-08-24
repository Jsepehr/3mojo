/// Sostituto per il web: ML Kit non ha build web, quindi non c'è modo di
/// eseguire davvero il controllo — si assume "c'è un volto" per non
/// bloccare i test da browser. Resta comunque obbligatorio scattare o
/// caricare un selfie, si salta solo la verifica del contenuto.
Future<bool> detectFace(String imagePath) async => true;
