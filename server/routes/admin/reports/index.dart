import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/admin_reports_api.dart';

/// `GET /admin/reports` — i record di moderazione da rivedere (solo
/// metadati, niente selfie). Spento senza `ADMIN_TOKEN`, solo su TLS, con
/// `Authorization: Bearer <token>`: vedi `AdminReportsApi`.
Future<Response> onRequest(RequestContext context) =>
    AdminReportsApi.instance.list(AdminRequest.fromContext(context));
