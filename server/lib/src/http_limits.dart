import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Il corpo di una richiesta HTTP supera [maxHttpBodyBytes].
class BodyTooLargeException implements Exception {
  const BodyTooLargeException();
}

/// Tetto al corpo delle richieste HTTP del server (`/paywall/*`): la più
/// grande è una transazione firmata di Apple (qualche KB) o un
/// `purchaseToken`; 64 KB ne lasciano a sufficienza. **Lo stesso limite va
/// messo anche nel reverse proxy** (`request_body max_size 64KB` nel
/// Caddyfile di `deploy/`): qui è la seconda linea, e l'unica con un proxy
/// che non lo impone.
const maxHttpBodyBytes = 64 * 1024;

/// Legge e decodifica il corpo JSON di [request] senza mai tenere in
/// memoria più di [maxBytes]: guarda `Content-Length` prima, e conta i byte
/// mentre arrivano (un corpo "chunked" senza lunghezza dichiarata si ferma
/// comunque al tetto).
///
/// Lancia [BodyTooLargeException] oltre il tetto e `FormatException` se non
/// è JSON valido (o non è UTF-8).
Future<Object?> readJsonBody(
  Request request, {
  int maxBytes = maxHttpBodyBytes,
}) async {
  final declared = int.tryParse(
    request.headers[HttpHeaders.contentLengthHeader] ?? '',
  );
  if (declared != null && declared > maxBytes) {
    throw const BodyTooLargeException();
  }
  final bytes = <int>[];
  await for (final chunk in request.bytes()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) throw const BodyTooLargeException();
  }
  return jsonDecode(utf8.decode(bytes));
}

/// La risposta 413 uniforme.
Response bodyTooLargeResponse() => Response.json(
  statusCode: HttpStatus.requestEntityTooLarge,
  body: {'error': 'Richiesta troppo grande', 'code': 'bodyTooLarge'},
);
