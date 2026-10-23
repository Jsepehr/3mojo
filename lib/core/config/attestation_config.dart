/// L'unico posto con la configurazione della **verifica del dispositivo**
/// (App Attest su iOS, Play Integrity su Android): il server la chiede solo
/// se è acceso con `ATTESTATION_MODE=log|enforce` (spento di default),
/// mandando un `challenge` dopo l'`hello` di una sessione nuova — vedi
/// `RealtimeConnection` e `server/routes/ws.dart`.
///
/// Cosa produce l'app, e cosa **no**: un'attestazione "questa è l'app vera
/// su un dispositivo vero", legata al nonce di quel socket, una volta per
/// sessione. Nessun id del dispositivo: su iOS la chiave App Attest è
/// **nuova a ogni sessione** e il suo `keyId` non viene salvato; su Android
/// il token Play Integrity non contiene identificativi. Nulla resta sul
/// telefono né sul server dopo la verifica.
///
/// ```
/// flutter build appbundle --release \
///   --dart-define=GOOGLE_CLOUD_PROJECT_NUMBER=<numero del progetto> \
///   --dart-define=API_BASE_URL=https://<server>
/// ```
///
/// Passi completi in `guida_per_sviluppatori.md` ("Per attivare la verifica
/// del dispositivo").
class AttestationConfig {
  const AttestationConfig._();

  /// Numero (non l'id testuale) del progetto **Google Cloud** collegato
  /// all'app in Play Console, dove è abilitata la Play Integrity API: serve
  /// a `StandardIntegrityManager.prepareIntegrityToken`. `0` = non
  /// configurato: su Android l'attestazione non parte (e con
  /// `ATTESTATION_MODE=enforce` il server rifiuterebbe la sessione).
  /// TODO(attestation): impostarlo quando il progetto Google Cloud esiste
  /// (o passarlo con `--dart-define=GOOGLE_CLOUD_PROJECT_NUMBER=...`).
  static const int googleCloudProjectNumber = int.fromEnvironment(
    'GOOGLE_CLOUD_PROJECT_NUMBER',
  );

  /// Nei build di debug si usa l'attestazione **finta**
  /// (`AttestationDataSourceFakeImpl`), che il server accetta solo con
  /// `ATTESTATION_ALLOW_FAKE=true` su un server non pubblico. Con
  /// `--dart-define=ATTESTATION_NATIVE=true` anche un build di debug usa
  /// App Attest / Play Integrity veri (per provarli su un dispositivo con
  /// la firma e l'entitlement giusti). Nei build di release è sempre vera.
  static const bool nativeInDebug = bool.fromEnvironment('ATTESTATION_NATIVE');

  /// Prefisso del token finto: lo stesso di `FakeAttestationVerifier` sul
  /// server. Non è un segreto.
  static const String fakeTokenPrefix = 'raen-fake-attestation:';

  /// La regola di scelta, separata per poterla provare: il finto **solo**
  /// in debug e solo se non si è chiesto il nativo.
  static bool useFake({
    required bool debugBuild,
    bool native = nativeInDebug,
  }) => debugBuild && !native;
}
