import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/admin_reports_api.dart';
import 'package:threemojo_server/src/moderation_records.dart';
import 'package:threemojo_server/src/rate_limiters.dart';

const _token = 'admin-token-0123456789-abcdefghij-xyz';
const _id = '0123456789abcdef0123456789abcdef';
final _selfie = [0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9];

AdminRequest _request({
  HttpMethod method = HttpMethod.get,
  String remote = '127.0.0.1',
  String? token = _token,
  Map<String, String> extraHeaders = const {},
}) => AdminRequest(
  method: method,
  remoteAddress: remote,
  headers: {
    if (token != null) 'authorization': 'Bearer $token',
    ...extraHeaders,
  },
);

void main() {
  late Directory tempDir;
  late ModerationRecordStore records;

  AdminReportsApi api({
    String? token = _token,
    bool tls = false,
    bool allowInsecureLoopback = true,
    Set<String> trustedProxies = const {},
    SlidingWindowRateLimiter? rateLimiter,
  }) => AdminReportsApi(
    token: token,
    records: records,
    serverHasTls: tls,
    trustedProxies: trustedProxies,
    allowInsecureLoopback: allowInsecureLoopback,
    rateLimiter: rateLimiter,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('admin_api_test');
    records = ModerationRecordStore(
      directory: Directory('${tempDir.path}/records'),
      key: List<int>.generate(32, (i) => i),
      now: () => DateTime.utc(2026, 1, 2),
    );
    await records.save(
      ModerationRecord(
        id: _id,
        createdAt: DateTime.utc(2026, 1, 1, 10, 5),
        updatedAt: DateTime.utc(2026, 1, 1, 10, 9),
        reasons: const {'fakePhoto': 2},
        reportCount: 2,
        autoClosed: false,
        selfieBase64: base64Encode(_selfie),
      ),
    );
  });
  tearDown(() => tempDir.delete(recursive: true));

  test('without ADMIN_TOKEN (or with a short one) everything is 404', () async {
    for (final token in [null, '', 'short']) {
      final disabled = api(token: token);
      expect(disabled.isEnabled, isFalse);
      expect((await disabled.list(_request())).statusCode, 404);
      expect((await disabled.selfie(_request(), _id)).statusCode, 404);
      expect(
        (await disabled.delete(
          _request(method: HttpMethod.delete),
          _id,
        )).statusCode,
        404,
      );
    }
    expect(AdminReportsApi.configurationProblem(const {}), isNotNull);
    expect(
      AdminReportsApi.configurationProblem(const {'ADMIN_TOKEN': _token}),
      isNull,
    );
  });

  test('a missing or wrong token is 401', () async {
    expect((await api().list(_request(token: null))).statusCode, 401);
    expect((await api().list(_request(token: '${_token}x'))).statusCode, 401);
    expect(
      (await api().list(
        _request(token: null, extraHeaders: {'authorization': _token}),
      )).statusCode,
      401,
    );
  });

  test('plain HTTP is refused unless TLS, a trusted HTTPS proxy, or the '
      'explicit loopback opt-in', () async {
    final strict = api(allowInsecureLoopback: false);
    expect((await strict.list(_request())).statusCode, 403);
    // The opt-in only works from loopback.
    expect((await api().list(_request(remote: '10.0.0.5'))).statusCode, 403);

    expect(
      (await api(tls: true).list(_request(remote: '10.0.0.5'))).statusCode,
      200,
    );

    final proxied = api(
      allowInsecureLoopback: false,
      trustedProxies: const {'10.0.0.1'},
    );
    expect(
      (await proxied.list(
        _request(
          remote: '10.0.0.1',
          extraHeaders: {'x-forwarded-proto': 'https'},
        ),
      )).statusCode,
      200,
    );
    expect(
      (await proxied.list(
        _request(
          remote: '10.0.0.1',
          extraHeaders: {'x-forwarded-proto': 'http'},
        ),
      )).statusCode,
      403,
    );
    // The header means nothing from an untrusted address.
    expect(
      (await proxied.list(
        _request(
          remote: '10.0.0.9',
          extraHeaders: {'x-forwarded-proto': 'https'},
        ),
      )).statusCode,
      403,
    );
  });

  test('requests are rate limited per IP, before authentication', () async {
    final limited = api(
      rateLimiter: SlidingWindowRateLimiter(
        maxActions: 2,
        window: const Duration(minutes: 10),
      ),
    );
    expect((await limited.list(_request(token: 'wrong'))).statusCode, 401);
    expect((await limited.list(_request())).statusCode, 200);
    expect((await limited.list(_request())).statusCode, 429);
  });

  test('the list has the metadata, never the selfie', () async {
    final response = await api().list(_request());
    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    final body = await response.json() as Map<String, dynamic>;
    expect(body['recordsEnabled'], isTrue);
    final report = (body['reports'] as List).single as Map<String, dynamic>;
    expect(report, {
      'id': _id,
      'createdAt': '2026-01-01T10:05:00.000Z',
      'updatedAt': '2026-01-01T10:09:00.000Z',
      'expiresAt': '2026-01-31T10:05:00.000Z',
      'reasons': {'fakePhoto': 2},
      'reportCount': 2,
      'autoClosed': false,
      'hasSelfie': true,
    });
    expect(
      (await api().list(_request(method: HttpMethod.post))).statusCode,
      405,
    );
  });

  test('the selfie is served as a JPEG, not cached', () async {
    final response = await api().selfie(_request(), _id);
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'image/jpeg');
    expect(response.headers['cache-control'], 'no-store');
    expect(await response.bytes().expand((chunk) => chunk).toList(), _selfie);

    expect(
      (await api().selfie(
        _request(),
        'ffffffffffffffffffffffffffffffff',
      )).statusCode,
      404,
    );
  });

  test('a malformed id is 404 and never reaches the disk', () async {
    for (final id in ['../records', 'ABC', '$_id/..']) {
      expect((await api().selfie(_request(), id)).statusCode, 404);
      expect(
        (await api().delete(
          _request(method: HttpMethod.delete),
          id,
        )).statusCode,
        404,
      );
    }
  });

  test('DELETE resolves a report: 204, then it is gone', () async {
    final deleteRequest = _request(method: HttpMethod.delete);
    expect((await api().delete(_request(), _id)).statusCode, 405);
    expect((await api().delete(deleteRequest, _id)).statusCode, 204);
    expect((await api().delete(deleteRequest, _id)).statusCode, 404);
    expect(await records.list(), isEmpty);
  });
}
