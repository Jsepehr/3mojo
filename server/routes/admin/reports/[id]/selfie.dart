import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/admin_reports_api.dart';

/// `GET /admin/reports/<id>/selfie` — il selfie della persona segnalata
/// (`image/jpeg`, mai in cache). Protezioni in `AdminReportsApi`.
Future<Response> onRequest(RequestContext context, String id) =>
    AdminReportsApi.instance.selfie(AdminRequest.fromContext(context), id);
