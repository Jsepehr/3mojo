import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Un'attestazione del dispositivo pronta per il messaggio `attestation`
/// del protocollo realtime (vedi `server/routes/ws.dart`). Vive solo il
/// tempo di essere mandata: non viene mai salvata.
class DeviceAttestation {
  const DeviceAttestation._(this.platform, this._fields);

  /// Un token della Play Integrity API (Standard request).
  factory DeviceAttestation.android(String token) =>
      DeviceAttestation._('android', {'token': token});

  /// Una chiave App Attest appena generata e la sua attestazione (CBOR).
  factory DeviceAttestation.ios({
    required String keyId,
    required Uint8List attestationObject,
  }) => DeviceAttestation._('ios', {
    'keyId': keyId,
    'attestationObject': base64.encode(attestationObject),
  });

  /// L'attestazione finta dei build di debug.
  factory DeviceAttestation.fake(String token) =>
      DeviceAttestation._('fake', {'token': token});

  final String platform;
  final Map<String, String> _fields;

  /// I campi del messaggio `attestation` (senza `type`).
  Map<String, String> toJson() => {'platform': platform, ..._fields};

  /// `SHA-256(utf8(nonce))`: il `clientDataHash` di App Attest. Lo stesso
  /// calcolo di `AttestationChallenge.clientDataHash` sul server.
  static Uint8List clientDataHash(String nonce) =>
      Uint8List.fromList(sha256.convert(utf8.encode(nonce)).bytes);

  /// `hex(SHA-256(utf8(nonce)))`: il `requestHash` di Play Integrity. Lo
  /// stesso calcolo di `AttestationChallenge.requestHash` sul server.
  static String requestHash(String nonce) =>
      sha256.convert(utf8.encode(nonce)).toString();
}
