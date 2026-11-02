import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/attestation/attestation_gate.dart';
import 'package:threemojo_server/src/connection_hub.dart';
import 'package:threemojo_server/src/connection_limit.dart';
import 'package:threemojo_server/src/constant_time.dart';
import 'package:threemojo_server/src/ip_address.dart';
import 'package:threemojo_server/src/metrics.dart';
import 'package:threemojo_server/src/paywall_store.dart';
import 'package:threemojo_server/src/session_lifecycle.dart';
import 'package:threemojo_server/src/session_store.dart';

/// `GET /metrics`: contatori **aggregati** per il monitoraggio (sessioni
/// connesse e in grazia, messaggi per tipo, `rejected` per motivo, esiti di
/// acquisti e attestazioni, record di moderazione salvati/falliti, RSS).
/// Solo numeri: nessun IP, posizione, pseudonimo, token (vedi `Metrics`).
///
/// **Accesso**: o da loopback **diretto** (la connessione è loopback *e* non
/// porta `X-Forwarded-For`: un proxy sullo stesso host farebbe sembrare
/// "locale" tutto Internet, quindi una richiesta inoltrata dal proxy non
/// conta), o con `Authorization: Bearer <METRICS_TOKEN>` (almeno 32
/// caratteri, confronto a tempo costante) — pensato per uno scraper nella
/// rete interna. Altrimenti 404, come se non esistesse. Il Caddyfile di
/// `deploy/` non lo espone comunque all'esterno.
class MetricsApi {
  MetricsApi({
    required String? token,
    Metrics? metrics,
    Map<String, int> Function()? gauges,
    Map<String, int> Function()? attestations,
  }) : _token = token != null && token.length >= minTokenLength ? token : null,
       _metrics = metrics ?? Metrics.instance,
       _gauges = gauges ?? _liveGauges,
       _attestations = attestations ?? _liveAttestations;

  factory MetricsApi.fromEnvironment(Map<String, String> environment) =>
      MetricsApi(token: environment['METRICS_TOKEN']?.trim());

  static final MetricsApi instance = MetricsApi.fromEnvironment(
    Platform.environment,
  );

  static const minTokenLength = 32;

  final String? _token;
  final Metrics _metrics;
  final Map<String, int> Function() _gauges;
  final Map<String, int> Function() _attestations;

  static Map<String, int> _liveGauges() => {
    'connected': ConnectionHub.instance.connectedCount,
    'inGrace': SessionLifecycle.instance.graceCount,
    'known': SessionStore.instance.allSessions.length,
    'activeUnlocks': PaywallStore.instance.activeCount,
    'webSocketConnections': WebSocketConnectionLimit.instance.active,
  };

  static Map<String, int> _liveAttestations() => {
    for (final entry in AttestationGate.instance.counts.entries)
      entry.key.name: entry.value,
  };

  Response handle({
    required HttpMethod method,
    required String remoteAddress,
    required Map<String, String> headers,
  }) {
    final forwarded = (headers['x-forwarded-for'] ?? '').trim().isNotEmpty;
    final fromLocalhost = isLoopbackIp(remoteAddress) && !forwarded;

    final authorization = headers['authorization'] ?? '';
    const prefix = 'Bearer ';
    final provided = authorization.startsWith(prefix)
        ? authorization.substring(prefix.length).trim()
        : '';
    final token = _token;
    final withToken = token != null && constantTimeEquals(provided, token);

    if (!fromLocalhost && !withToken) {
      return Response(statusCode: HttpStatus.notFound);
    }
    if (method != HttpMethod.get) {
      return Response(statusCode: HttpStatus.methodNotAllowed);
    }
    return Response.json(
      headers: {'Cache-Control': 'no-store'},
      body: _metrics.snapshot(gauges: _gauges(), attestations: _attestations()),
    );
  }
}
