import 'attestation_challenge.dart';
import 'attestation_verifier.dart';
import 'play_integrity_api.dart';

/// Verifica un token della **Play Integrity API, Standard request**
/// facendolo decodificare a Google ([PlayIntegrityApi]) e controllando il
/// verdetto (`tokenPayloadExternal`):
/// - `requestDetails.requestPackageName` e `appIntegrity.packageName` =
///   [packageName] (`GOOGLE_PACKAGE_NAME`);
/// - `requestDetails.requestHash` = `hex(SHA-256(utf8(nonce)))` del
///   challenge di **questo** socket (`AttestationChallenge.requestHash`):
///   lega il token alla connessione, un token di un altro socket non vale;
/// - `requestDetails.timestampMillis` recente ([maxTokenAge], con
///   [maxClockSkew] di tolleranza "dal futuro");
/// - `appIntegrity.appRecognitionVerdict` = `PLAY_RECOGNIZED` (l'APK è
///   quello pubblicato su Play, non ricompilato o modificato);
/// - `deviceIntegrity.deviceRecognitionVerdict` contiene
///   `MEETS_DEVICE_INTEGRITY` (dispositivo Android certificato, non un
///   emulatore né un dispositivo con il bootloader sbloccato e un sistema
///   modificato). `MEETS_BASIC_INTEGRITY` da solo **non** basta.
///
/// Perché la **Standard** API e non la Classic: è quella che Google
/// consiglia per le richieste frequenti — il verdetto viene preparato in
/// anticipo dal Play Store (meno latenza allo Start, meno chiamate ai
/// server di Google), e il legame con la richiesta passa da `requestHash`
/// invece che dal `nonce`: per un challenge già monouso e legato al socket
/// il risultato è lo stesso. La Classic resta pensata per azioni rare.
///
/// **Privacy**: del verdetto si usano solo i campi sopra; `accountDetails`
/// (licenza), `environmentDetails` ed eventuali campi facoltativi non si
/// guardano, e nulla del verdetto viene salvato o scritto nel log (solo
/// l'esito, vedi `AttestationGate`). Il token Play Integrity non contiene
/// identificativi del dispositivo né dell'account.
class PlayIntegrityVerifier implements AttestationVerifier {
  PlayIntegrityVerifier({
    required this.packageName,
    required PlayIntegrityApi api,
    DateTime Function()? now,
    this.maxTokenAge = const Duration(minutes: 2),
    this.maxClockSkew = const Duration(minutes: 1),
  }) : _api = api,
       _now = now ?? DateTime.now;

  final String packageName;
  final PlayIntegrityApi _api;
  final DateTime Function() _now;
  final Duration maxTokenAge;
  final Duration maxClockSkew;

  /// Lunghezza massima di un token da mandare a Google.
  static const maxTokenLength = 8 * 1024;

  @override
  AttestationPlatform get platform => AttestationPlatform.android;

  @override
  Future<void> verify(
    AttestationEvidence evidence, {
    required String nonce,
  }) async {
    if (evidence is! PlayIntegrityEvidence ||
        evidence.token.length > maxTokenLength) {
      throw const AttestationRejectedException(AttestationRejection.malformed);
    }
    final payload = await _api.decodeIntegrityToken(evidence.token);
    checkVerdict(payload, nonce: nonce);
  }

  /// I controlli sul verdetto decodificato (pubblico per i test).
  void checkVerdict(Map<String, dynamic> payload, {required String nonce}) {
    final request = _map(payload['requestDetails']);
    final app = _map(payload['appIntegrity']);
    final device = _map(payload['deviceIntegrity']);
    if (request == null || app == null || device == null) {
      throw const AttestationRejectedException(
        AttestationRejection.malformed,
        'verdetto incompleto',
      );
    }

    if (request['requestPackageName'] != packageName ||
        app['packageName'] != packageName) {
      throw const AttestationRejectedException(AttestationRejection.wrongApp);
    }
    if (request['requestHash'] != AttestationChallenge.requestHash(nonce)) {
      throw const AttestationRejectedException(AttestationRejection.wrongNonce);
    }

    final rawTimestamp = request['timestampMillis'];
    final millis = rawTimestamp is int
        ? rawTimestamp
        : int.tryParse('${rawTimestamp ?? ''}');
    if (millis == null) {
      throw const AttestationRejectedException(
        AttestationRejection.malformed,
        'timestampMillis mancante',
      );
    }
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    final now = _now().toUtc();
    if (now.difference(issuedAt) > maxTokenAge ||
        issuedAt.difference(now) > maxClockSkew) {
      throw const AttestationRejectedException(AttestationRejection.stale);
    }

    if (app['appRecognitionVerdict'] != 'PLAY_RECOGNIZED') {
      throw AttestationRejectedException(
        AttestationRejection.unrecognizedApp,
        '${app['appRecognitionVerdict']}',
      );
    }
    final verdicts = device['deviceRecognitionVerdict'];
    if (verdicts is! List || !verdicts.contains('MEETS_DEVICE_INTEGRITY')) {
      throw const AttestationRejectedException(
        AttestationRejection.deviceNotTrusted,
      );
    }
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;
}
