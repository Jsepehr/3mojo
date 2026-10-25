import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:threemojo_app/core/unlock/unlock_token_store.dart';
import 'package:threemojo_app/features/nearby/data/datasources/nearby_remote_data_source_fake_impl.dart';

import '../../support/fake_repositories.dart';

void main() {
  Future<List<bool>> lockedFlags({required bool crowded}) async {
    final dataSource = NearbyRemoteDataSourceFakeImpl(
      unlockTokenStore: UnlockTokenStore.inMemory(),
      viewerMustStayPut: false,
      peopleComeAndGo: false,
      crowded: crowded,
    );
    final people = await dataSource
        .connect(
          sessionId: 'session',
          latitude: 0,
          longitude: 0,
          profile: testProfile,
          selfieBytes: Uint8List(0),
        )
        .first;
    await dataSource.disconnect();
    return [for (final person in people) person.isLocked];
  }

  test('la modalità finta di sviluppo ha 12 persone, molte bloccate', () async {
    final flags = await lockedFlags(crowded: true);

    expect(flags, hasLength(12));
    // Un terzo dei più lontani gratis (min 2): 4 libere, 8 da sbloccare.
    expect(flags.where((locked) => locked), hasLength(8));
  });

  test('la demo resta a 5 persone', () async {
    expect(await lockedFlags(crowded: false), hasLength(5));
  });
}
