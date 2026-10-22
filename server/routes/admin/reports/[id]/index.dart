import 'package:dart_frog/dart_frog.dart';
import 'package:threemojo_server/src/admin_reports_api.dart';

/// `DELETE /admin/reports/<id>` — segnalazione risolta: il record di
/// moderazione viene cancellato subito (204). Protezioni in
/// `AdminReportsApi`.
Future<Response> onRequest(RequestContext context, String id) =>
    AdminReportsApi.instance.delete(AdminRequest.fromContext(context), id);
