import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/utils/photo_bytes_cache.dart';

void main() {
  test('the same photo is decoded once and returned as the same instance', () {
    final cache = PhotoBytesCache();
    final photo = base64Encode([1, 2, 3]);

    final first = cache.decode(photo);
    final second = cache.decode(photo);

    expect(first, [1, 2, 3]);
    expect(identical(first, second), isTrue);
  });

  test('missing or malformed photos are null, never an exception', () {
    final cache = PhotoBytesCache();

    expect(cache.decode(null), isNull);
    expect(cache.decode(''), isNull);
    expect(cache.decode(42), isNull);
    expect(cache.decode('not-base64!!'), isNull);
  });

  test('keeps at most maxEntries photos', () {
    final cache = PhotoBytesCache(maxEntries: 2);
    final a = base64Encode([1]);
    final first = cache.decode(a);
    cache
      ..decode(base64Encode([2]))
      ..decode(base64Encode([3]));

    expect(identical(cache.decode(a), first), isFalse);
  });
}
