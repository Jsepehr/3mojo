import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '/core/config/attestation_config.dart';
import '/core/errors/exceptions.dart';
import 'attestation_data_source.dart';
import 'device_attestation.dart';

/// Implementazione **reale**, tramite il canale nativo nostro
/// `raen/attestation` (come `raen/face_detection`, nessun plugin di terzi):
/// - **Android** (`AttestationChannel.kt`): Play Integrity API, **Standard
///   request**, con `requestHash = hex(SHA-256(utf8(nonce)))` e il numero
///   del progetto Google Cloud ([AttestationConfig.googleCloudProjectNumber]).
///   Standard e non Classic: Google la consiglia per le richieste frequenti
///   (verdetto preparato in anticipo dal Play Store: meno latenza allo
///   Start, meno chiamate), e il legame col challenge passa da
///   `requestHash` invece che dal `nonce` con lo stesso effetto;
/// - **iOS** (`AppDelegate.swift`, `AttestationChannel`):
///   `DCAppAttestService` — `generateKey` (una chiave **nuova a ogni
///   sessione**, mai salvata da noi) e `attestKey` con `clientDataHash =
///   SHA-256(utf8(nonce))`. Sul simulatore App Attest non esiste
///   (`isSupported == false`): errore `UNSUPPORTED`, l'app continua.
///
/// Gli hash si calcolano qui in Dart ([DeviceAttestation]), così sono gli
/// stessi su entrambe le piattaforme e si provano senza dispositivo.
///
/// Ogni errore (canale assente — web, desktop, test —, `PlatformException`,
/// configurazione mancante) diventa [AttestationUnavailableException].
class AttestationDataSourceImpl implements AttestationDataSource {
  AttestationDataSourceImpl({
    MethodChannel? channel,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
    int cloudProjectNumber = AttestationConfig.googleCloudProjectNumber,
  }) : _channel = channel ?? const MethodChannel('raen/attestation'),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb,
       _cloudProjectNumber = cloudProjectNumber;

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final bool _isWeb;
  final int _cloudProjectNumber;

  @override
  Future<DeviceAttestation> attest(String nonce) async {
    if (_isWeb) {
      throw const AttestationUnavailableException('No attestation on the web');
    }
    try {
      return switch (_platform) {
        TargetPlatform.android => await _playIntegrity(nonce),
        TargetPlatform.iOS => await _appAttest(nonce),
        _ => throw const AttestationUnavailableException(
          'No attestation on this platform',
        ),
      };
    } on PlatformException catch (e) {
      throw AttestationUnavailableException('${e.code}: ${e.message}');
    } on MissingPluginException {
      throw const AttestationUnavailableException('No attestation channel');
    }
  }

  Future<DeviceAttestation> _playIntegrity(String nonce) async {
    if (_cloudProjectNumber <= 0) {
      throw const AttestationUnavailableException(
        'GOOGLE_CLOUD_PROJECT_NUMBER not configured',
      );
    }
    final token = await _channel.invokeMethod<String>('playIntegrityToken', {
      'requestHash': DeviceAttestation.requestHash(nonce),
      'cloudProjectNumber': _cloudProjectNumber,
    });
    if (token == null || token.isEmpty) {
      throw const AttestationUnavailableException('Empty integrity token');
    }
    return DeviceAttestation.android(token);
  }

  Future<DeviceAttestation> _appAttest(String nonce) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'appAttest',
      {'clientDataHash': DeviceAttestation.clientDataHash(nonce)},
    );
    final keyId = result?['keyId'];
    final attestationObject = result?['attestationObject'];
    if (keyId is! String ||
        keyId.isEmpty ||
        attestationObject is! Uint8List ||
        attestationObject.isEmpty) {
      throw const AttestationUnavailableException(
        'Incomplete App Attest reply',
      );
    }
    return DeviceAttestation.ios(
      keyId: keyId,
      attestationObject: attestationObject,
    );
  }
}
