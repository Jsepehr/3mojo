import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/client_ip.dart';
import 'package:threemojo_server/src/constant_time.dart';
import 'package:threemojo_server/src/moderation_records.dart';
import 'package:threemojo_server/src/rate_limiters.dart';

/// Una chiamata a un endpoint admin, già separata dal `RequestContext` di
/// Dart Frog (così la logica si prova senza un vero socket).
class AdminRequest {
  const AdminRequest({
    required this.method,
    required this.remoteAddress,
    required this.headers,
  });

  factory AdminRequest.fromContext(RequestContext context) => AdminRequest(
    method: context.request.method,
    remoteAddress: context.request.connectionInfo.remoteAddress.address,
    headers: context.request.headers,
  );

  final HttpMethod method;
  final String remoteAddress;
  final Map<String, String> headers;
}

/// Gli endpoint per la **revisione umana** dei record di moderazione
/// (`ModerationRecordStore`):
/// - `GET /admin/reports` — lista dei metadati (niente selfie);
/// - `GET /admin/reports/<id>/selfie` — il selfie segnalato (`image/jpeg`);
/// - `DELETE /admin/reports/<id>` — segnalazione risolta: il record sparisce
///   (204).
///
/// Controlli, in quest'ordine:
/// 1. **spenti** se `ADMIN_TOKEN` manca o è più corto di [minTokenLength]
///    caratteri: 404, come se non esistessero (come `/debug/sessions`);
/// 2. **limite per IP** ([rateLimiter], prima dell'autenticazione: tentare
///    token costa): 429;
/// 3. **solo su TLS** ([isSecure]): il server serve TLS da sé
///    (`TLS_CERT_PATH`/`TLS_KEY_PATH`), oppure la connessione arriva da un
///    proxy fidato (`TRUSTED_PROXY`) che dice `X-Forwarded-Proto: https`,
///    oppure `ADMIN_ALLOW_INSECURE_HTTP=true` **e** la connessione è da
///    loopback (solo sviluppo locale). Altrimenti 403: il token e i selfie
///    non devono mai viaggiare in chiaro;
/// 4. `Authorization: Bearer <ADMIN_TOKEN>`, confronto a tempo costante:
///    altrimenti 401.
///
/// L'header `Authorization` **non** è tra quelli ammessi dai CORS del
/// middleware (`routes/_middleware.dart`): un browser non può chiamare
/// questi endpoint da un'altra origine. Si usano da riga di comando (curl)
/// o da uno strumento interno.
class AdminReportsApi {
  AdminReportsApi({
    required String? token,
    required this.records,
    required this.serverHasTls,
    required this.trustedProxies,
    this.allowInsecureLoopback = false,
    SlidingWindowRateLimiter? rateLimiter,
  }) : _token = token != null && token.length >= minTokenLength ? token : null,
       rateLimiter =
           rateLimiter ??
           SlidingWindowRateLimiter(
             maxActions: maxRequestsPerWindow,
             window: rateLimitWindow,
           );

  /// Configurazione da [environment] (vedi la doc della classe).
  factory AdminReportsApi.fromEnvironment(
    Map<String, String> environment, {
    required ModerationRecordStore records,
  }) {
    final token = environment[tokenEnvironmentVariable]?.trim() ?? '';
    final certPath = environment['TLS_CERT_PATH'] ?? '';
    final keyPath = environment['TLS_KEY_PATH'] ?? '';
    return AdminReportsApi(
      token: token,
      records: records,
      serverHasTls: certPath.isNotEmpty && keyPath.isNotEmpty,
      trustedProxies: trustedProxiesFromEnvironment(environment),
      allowInsecureLoopback:
          environment[allowInsecureEnvironmentVariable]?.trim().toLowerCase() ==
          'true',
    );
  }

  static final AdminReportsApi instance = AdminReportsApi.fromEnvironment(
    Platform.environment,
    records: ModerationRecordStore.instance,
  );

  static const tokenEnvironmentVariable = 'ADMIN_TOKEN';
  static const allowInsecureEnvironmentVariable = 'ADMIN_ALLOW_INSECURE_HTTP';
  static const minTokenLength = 32;
  static const maxRequestsPerWindow = 120;
  static const rateLimitWindow = Duration(minutes: 10);

  final String? _token;
  final ModerationRecordStore records;
  final bool serverHasTls;
  final Set<String> trustedProxies;
  final bool allowInsecureLoopback;
  final SlidingWindowRateLimiter rateLimiter;

  bool get isEnabled => _token != null;

  /// Perché gli endpoint sono spenti, o `null` se sono accesi — per il log
  /// all'avvio (`main.dart`).
  static String? configurationProblem(Map<String, String> environment) {
    final token = environment[tokenEnvironmentVariable]?.trim() ?? '';
    if (token.isEmpty) {
      return '$tokenEnvironmentVariable non impostata: /admin/reports spento.';
    }
    if (token.length < minTokenLength) {
      return '$tokenEnvironmentVariable più corta di $minTokenLength '
          'caratteri: /admin/reports spento.';
    }
    return null;
  }

  /// `true` se la richiesta è arrivata cifrata (vedi la doc della classe).
  bool isSecure(AdminRequest request) {
    if (serverHasTls) return true;
    if (trustedProxies.contains(request.remoteAddress)) {
      // Più proxy in fila aggiungono in coda: conta l'ultimo valore.
      final proto = request.headers['x-forwarded-proto'] ?? '';
      final last = proto.split(',').last.trim().toLowerCase();
      return last == 'https';
    }
    final address = InternetAddress.tryParse(request.remoteAddress);
    return allowInsecureLoopback && (address?.isLoopback ?? false);
  }

  Response? _guard(AdminRequest request) {
    final token = _token;
    if (token == null) return Response(statusCode: HttpStatus.notFound);

    final clientIp = resolveClientIp(
      remoteAddress: request.remoteAddress,
      forwardedFor: request.headers['x-forwarded-for'],
      trustedProxies: trustedProxies,
    );
    if (!rateLimiter.tryAcquire(clientIp)) {
      return Response.json(
        statusCode: HttpStatus.tooManyRequests,
        body: {'error': 'Troppe richieste, riprova tra qualche minuto'},
      );
    }
    if (!isSecure(request)) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Solo su HTTPS'},
      );
    }

    final authorization = request.headers['authorization'] ?? '';
    const prefix = 'Bearer ';
    final provided = authorization.startsWith(prefix)
        ? authorization.substring(prefix.length).trim()
        : '';
    if (!constantTimeEquals(provided, token)) {
      return Response(
        statusCode: HttpStatus.unauthorized,
        headers: {'WWW-Authenticate': 'Bearer'},
      );
    }
    return null;
  }

  static const _noStore = {'Cache-Control': 'no-store'};

  /// `GET /admin/reports`.
  Future<Response> list(AdminRequest request) => _safely(() async {
    final denied = _guard(request);
    if (denied != null) return denied;
    if (request.method != HttpMethod.get) {
      return Response(statusCode: HttpStatus.methodNotAllowed);
    }
    final all = await records.list();
    return Response.json(
      headers: _noStore,
      body: {
        'recordsEnabled': records.isEnabled,
        'retentionDays': records.retention.inDays,
        'reports': [
          for (final record in all)
            record.toMetadataJson(retention: records.retention),
        ],
      },
    );
  });

  /// `GET /admin/reports/<id>/selfie`.
  Future<Response> selfie(AdminRequest request, String id) => _safely(() async {
    final denied = _guard(request);
    if (denied != null) return denied;
    if (request.method != HttpMethod.get) {
      return Response(statusCode: HttpStatus.methodNotAllowed);
    }
    if (!ModerationRecordStore.isValidId(id)) {
      return Response(statusCode: HttpStatus.notFound);
    }
    final record = await records.read(id);
    if (record == null || record.selfieBase64.isEmpty) {
      return Response(statusCode: HttpStatus.notFound);
    }
    return Response.bytes(
      body: base64Decode(record.selfieBase64),
      headers: {..._noStore, HttpHeaders.contentTypeHeader: 'image/jpeg'},
    );
  });

  /// `DELETE /admin/reports/<id>`.
  Future<Response> delete(AdminRequest request, String id) => _safely(() async {
    final denied = _guard(request);
    if (denied != null) return denied;
    if (request.method != HttpMethod.delete) {
      return Response(statusCode: HttpStatus.methodNotAllowed);
    }
    if (!ModerationRecordStore.isValidId(id)) {
      return Response(statusCode: HttpStatus.notFound);
    }
    final deleted = await records.delete(id);
    return Response(
      statusCode: deleted ? HttpStatus.noContent : HttpStatus.notFound,
    );
  });

  /// Un errore di disco non deve diventare uno stack trace in risposta.
  static Future<Response> _safely(Future<Response> Function() handler) async {
    try {
      return await handler();
    } catch (error, stackTrace) {
      developer.log(
        'Endpoint admin fallito',
        error: error,
        stackTrace: stackTrace,
      );
      return Response(statusCode: HttpStatus.internalServerError);
    }
  }
}
