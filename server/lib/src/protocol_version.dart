import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// La versione del **protocollo** tra app e server (messaggi di `/ws` e
/// rotte `/paywall/*`), diversa dalla versione dell'app: sale solo quando
/// un cambiamento rende un client vecchio incapace di parlare col server.
///
/// **Politica**: il server accetta la versione attuale [currentVersion] (N)
/// e la precedente (N-1), così un rilascio graduale — app nuova negli store
/// che arriva in giorni, server già aggiornato — non rompe nessuno. Un
/// client più vecchio riceve `{"type": "error", "code": "updateRequired"}` e
/// il socket si chiude con [closeCodeUpdateRequired]; sulle rotte HTTP,
/// 426. Il client più **nuovo** del server è sempre accettato (ignora ciò
/// che non conosce, e il server ignora i campi sconosciuti).
///
/// Un client che non dichiara nulla vale `0`: le app uscite prima di questo
/// meccanismo. Con N = 1, il minimo è 0 e passano tutte; quando N diventerà
/// 2 il minimo salirà a 1 e quelle senza versione dovranno aggiornare.
/// `MIN_PROTOCOL_VERSION` alza il minimo a mano (per forzare un
/// aggiornamento senza cambiare codice), mai oltre [currentVersion].
///
/// **Regola di compatibilità** (per chi modifica il protocollo): si
/// aggiungono campi e tipi di messaggio senza alzare la versione — chi non
/// li conosce li ignora. Si alza la versione solo per cambiare il
/// significato di qualcosa che esiste.
class ProtocolPolicy {
  const ProtocolPolicy({this.current = currentVersion, int? minimum})
    : minimum = minimum ?? (current > 0 ? current - 1 : 0);

  /// Dalla variabile `MIN_PROTOCOL_VERSION` (intero ≥ 0): il minimo di
  /// default è N-1.
  factory ProtocolPolicy.fromEnvironment(Map<String, String> environment) {
    final raw = int.tryParse(
      (environment['MIN_PROTOCOL_VERSION'] ?? '').trim(),
    );
    if (raw == null || raw < 0) return const ProtocolPolicy();
    return ProtocolPolicy(minimum: raw > currentVersion ? currentVersion : raw);
  }

  static final ProtocolPolicy instance = ProtocolPolicy.fromEnvironment(
    Platform.environment,
  );

  /// N: la versione che parla questo server.
  static const currentVersion = 1;

  /// Codice di chiusura WebSocket per "aggiorna l'app" (4011 è la verifica
  /// del dispositivo).
  static const closeCodeUpdateRequired = 4012;

  /// Header con cui i client dichiarano la versione sulle rotte HTTP.
  static const httpHeader = 'x-raen-protocol';

  final int current;
  final int minimum;

  /// Il numero dichiarato da un client: un intero ≥ 0, altrimenti `0`.
  static int parse(Object? raw) {
    if (raw is int && raw >= 0) return raw;
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed >= 0) return parsed;
    }
    return 0;
  }

  bool isSupported(int version) => version >= minimum;

  /// `null` se la richiesta può procedere, altrimenti la risposta 426. Va
  /// chiamata all'inizio delle rotte `/paywall/*`.
  Response? checkHttp(Map<String, String> headers) {
    if (isSupported(parse(headers[httpHeader]))) return null;
    return Response.json(
      statusCode: HttpStatus.upgradeRequired,
      headers: {httpHeader: '$current'},
      body: {
        'error': 'Aggiorna l\'app',
        'code': 'updateRequired',
        'minProtocol': minimum,
        'protocol': current,
      },
    );
  }
}
