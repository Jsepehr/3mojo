import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;

/// Il **challenge** di un socket: un nonce casuale che il server manda
/// (`{"type": "challenge", "nonce": ...}`) dopo un `hello` che aprirebbe
/// una sessione nuova, e a cui l'attestazione del dispositivo deve essere
/// legata. Vale **una volta sola** ([consume]) e per poco ([ttl]).
///
/// Vive solo dentro il `SocketSession` che l'ha emesso, in RAM: un
/// challenge non esiste fuori dal suo socket, quindi un'attestazione
/// prodotta per un socket non vale su un altro (nonce diverso) e nessuna
/// tabella condivisa di nonce cresce col traffico.
///
/// Come ci si lega al nonce (le due piattaforme lo ricevono uguale, come
/// testo):
/// - **iOS** (App Attest): `clientDataHash = SHA-256(utf8(nonce))`
///   ([clientDataHash]), passato a `attestKey`;
/// - **Android** (Play Integrity Standard): `requestHash =
///   hex(SHA-256(utf8(nonce)))` ([requestHash]), passato alla richiesta del
///   token e restituito da Google nel verdetto.
class AttestationChallenge {
  AttestationChallenge._(this.nonce, this.issuedAt, this.ttl);

  /// Un challenge nuovo: 32 byte casuali (`Random.secure`) in base64url
  /// senza `=`.
  factory AttestationChallenge.issue({
    required DateTime now,
    Duration ttl = defaultTtl,
    Random? random,
  }) {
    final source = random ?? Random.secure();
    final bytes = Uint8List(nonceBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = source.nextInt(256);
    }
    return AttestationChallenge._(
      base64Url.encode(bytes).replaceAll('=', ''),
      now,
      ttl,
    );
  }

  static const nonceBytes = 32;

  /// Quanto vale un challenge: abbastanza per generare una chiave e
  /// chiedere l'attestazione ad Apple/Google anche su una rete lenta,
  /// abbastanza poco perché non si possa "fare scorta" di attestazioni.
  static const defaultTtl = Duration(seconds: 20);

  final String nonce;
  final DateTime issuedAt;
  final Duration ttl;
  bool _consumed = false;

  bool get isConsumed => _consumed;

  /// Usa il challenge: `true` solo la prima volta **e** se non è scaduto a
  /// [now]. Dopo, sempre `false` (anche se il primo uso è fallito).
  bool consume(DateTime now) {
    if (_consumed) return false;
    _consumed = true;
    return !now.isAfter(issuedAt.add(ttl)) && !now.isBefore(issuedAt);
  }

  /// `SHA-256(utf8(nonce))`: il `clientDataHash` di App Attest.
  static Uint8List clientDataHash(String nonce) =>
      SHA256Digest().process(Uint8List.fromList(utf8.encode(nonce)));

  /// `hex(SHA-256(utf8(nonce)))`: il `requestHash` di Play Integrity.
  static String requestHash(String nonce) => clientDataHash(
    nonce,
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
