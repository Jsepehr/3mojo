import 'device_attestation.dart';

/// Produce l'attestazione del dispositivo per il challenge del server
/// (`RealtimeConnection`, prima del `welcome` di una sessione nuova).
///
/// Sta in `core/` accanto a `RealtimeConnection`, l'unica che la usa: è un
/// pezzo del canale condiviso, non di una feature.
abstract class AttestationDataSource {
  /// Un'attestazione legata a [nonce]. Lancia
  /// `AttestationUnavailableException` se qui non si può (simulatore iOS,
  /// web, Play Services assenti, configurazione mancante, errore di Apple o
  /// Google): chi chiama manda allora la risposta senza attestazione e
  /// decide il server.
  Future<DeviceAttestation> attest(String nonce);
}
