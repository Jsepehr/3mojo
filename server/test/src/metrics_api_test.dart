import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';
import 'package:threemojo_server/src/metrics.dart';
import 'package:threemojo_server/src/metrics_api.dart';

final _token = 'm' * 32;

MetricsApi _api({String? token, Metrics? metrics}) => MetricsApi(
  token: token,
  metrics: metrics ?? Metrics.forTest(),
  gauges: () => {'connected': 3, 'inGrace': 1},
  attestations: () => {'valid': 2},
);

Response _call(
  MetricsApi api, {
  String remote = '127.0.0.1',
  Map<String, String> headers = const {},
  HttpMethod method = HttpMethod.get,
}) => api.handle(method: method, remoteAddress: remote, headers: headers);

void main() {
  test(
    'loopback (any form) can read it; the answer is only counters',
    () async {
      final metrics = Metrics.forTest()
        ..message('presence')
        ..message('presence')
        ..message('chatMessage')
        ..message('not-a-real-type')
        ..rejected('notNearby')
        ..purchase('granted')
        ..moderationRecord(saved: true)
        ..moderationRecord(saved: false)
        ..connection('accepted');

      for (final remote in ['127.0.0.1', '::1', '::ffff:127.0.0.1']) {
        final response = _call(_api(metrics: metrics), remote: remote);
        expect(response.statusCode, 200, reason: remote);
      }
      final body =
          jsonDecode(await _call(_api(metrics: metrics)).body()) as Map;
      expect(body['sessions'], {'connected': 3, 'inGrace': 1});
      expect(body['messages'], {'presence': 2, 'chatMessage': 1, 'other': 1});
      expect(body['rejected'], {'notNearby': 1});
      expect(body['purchases'], {'granted': 1});
      expect(body['attestations'], {'valid': 2});
      expect(body['moderationRecords'], {'saved': 1, 'failed': 1});
      expect(body['connections'], {'accepted': 1});
      expect(body['rssBytes'], isA<int>());
      expect(body['uptimeSeconds'], isA<int>());
    },
  );

  test('from elsewhere it is a 404, as if it did not exist', () {
    expect(_call(_api(), remote: '203.0.113.7').statusCode, 404);
    expect(_call(_api(token: _token), remote: '203.0.113.7').statusCode, 404);
  });

  test('a loopback request forwarded by a proxy is NOT local', () {
    // Caddy on the same host: every Internet client looks like 127.0.0.1.
    expect(
      _call(
        _api(),
        remote: '127.0.0.1',
        headers: {'x-forwarded-for': '203.0.113.7'},
      ).statusCode,
      404,
    );
  });

  test('with METRICS_TOKEN: the right bearer works from anywhere, a wrong '
      'one does not', () {
    final api = _api(token: _token);
    expect(
      _call(
        api,
        remote: '10.0.0.9',
        headers: {'authorization': 'Bearer $_token'},
      ).statusCode,
      200,
    );
    expect(
      _call(
        api,
        remote: '10.0.0.9',
        headers: {'authorization': 'Bearer nope'},
      ).statusCode,
      404,
    );
  });

  test('a token shorter than 32 characters is ignored', () {
    final api = _api(token: 'short');
    expect(
      _call(
        api,
        remote: '10.0.0.9',
        headers: {'authorization': 'Bearer short'},
      ).statusCode,
      404,
    );
  });

  test('only GET', () {
    expect(_call(_api(), method: HttpMethod.post).statusCode, 405);
  });

  test('keys that are not plain identifiers collapse to other', () {
    final metrics = Metrics.forTest()
      ..rejected('203.0.113.7')
      ..rejected('some thing with spaces')
      ..purchase('x' * 100);
    final snapshot = metrics.snapshot();
    expect((snapshot['rejected'] as Map).keys, ['other']);
    expect((snapshot['purchases'] as Map).keys, ['other']);
  });
}
