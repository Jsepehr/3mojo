import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/metrics_api.dart';

/// `GET /metrics` — contatori aggregati, solo da loopback o con
/// `METRICS_TOKEN` (vedi `MetricsApi`).
Response onRequest(RequestContext context) => MetricsApi.instance.handle(
  method: context.request.method,
  remoteAddress: context.request.connectionInfo.remoteAddress.address,
  headers: context.request.headers,
);
