import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:threemojo_app/core/unlock/unlock_token_store.dart';

/// Un Keychain/Keystore che in questo momento non accetta scritture.
class _UnwritableStorage extends FlutterSecureStorage {
  const _UnwritableStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'unwritable');
}

// `UnlockTokenStore.instance` è un singleton che carica una volta sola: il
// suo scenario è uno solo, in sequenza; gli altri usano istanze proprie
// (`withStorage`).
void main() {
  test('migra il token da shared_preferences allo storage cifrato, '
      'senza race tra letture concorrenti', () async {
    final expiresAt = DateTime.now().add(const Duration(hours: 1));
    SharedPreferences.setMockInitialValues({
      'paywall_unlock_token': 'tok-123',
      'paywall_unlock_expires_at': expiresAt.toIso8601String(),
      'paywall_device_id': 'legacy-device-id',
    });
    FlutterSecureStorage.setMockInitialValues({});

    final store = UnlockTokenStore.instance;
    // Due letture partite insieme: entrambe devono vedere il token
    // migrato (prima la seconda poteva trovare `_loaded = true` e un
    // token ancora `null`).
    final results = await Future.wait([store.read(), store.read()]);
    expect(results, ['tok-123', 'tok-123']);

    // Niente più in chiaro in shared_preferences, deviceId compreso.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('paywall_unlock_token'), isNull);
    expect(prefs.getString('paywall_unlock_expires_at'), isNull);
    expect(prefs.getString('paywall_device_id'), isNull);

    // Ora sta nello storage cifrato.
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'paywall_unlock_token'), 'tok-123');

    // clear() cancella anche lo storage cifrato e notifica `null`.
    final emitted = <String?>[];
    final sub = store.changes.listen(emitted.add);
    await store.clear();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(emitted, [null]);
    expect(await store.read(), isNull);
    expect(await secure.read(key: 'paywall_unlock_token'), isNull);

    // save() scrive solo nello storage cifrato.
    await store.save('tok-456', const Duration(hours: 2));
    expect(await store.read(), 'tok-456');
    expect(await secure.read(key: 'paywall_unlock_token'), 'tok-456');
    expect(prefs.getString('paywall_unlock_token'), isNull);
  });

  test('se la scrittura cifrata fallisce il vecchio token resta in '
      'shared_preferences (si riprova al prossimo avvio), e intanto vale '
      'in memoria', () async {
    final expiresAt = DateTime.now().add(const Duration(hours: 1));
    SharedPreferences.setMockInitialValues({
      'paywall_unlock_token': 'tok-legacy',
      'paywall_unlock_expires_at': expiresAt.toIso8601String(),
      'paywall_device_id': 'legacy-device-id',
    });
    FlutterSecureStorage.setMockInitialValues({});

    final store = UnlockTokenStore.withStorage(const _UnwritableStorage());

    expect(await store.read(), 'tok-legacy');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('paywall_unlock_token'), 'tok-legacy');
    expect(prefs.getString('paywall_unlock_expires_at'), isNotNull);
    // Il vecchio identificativo fisso non serve a nulla: via comunque.
    expect(prefs.getString('paywall_device_id'), isNull);

    // Al "prossimo avvio" lo storage cifrato funziona: migrato e cancellato.
    final nextLaunch = UnlockTokenStore.withStorage(
      const FlutterSecureStorage(),
    );
    expect(await nextLaunch.read(), 'tok-legacy');
    expect(prefs.getString('paywall_unlock_token'), isNull);
    expect(prefs.getString('paywall_unlock_expires_at'), isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'paywall_unlock_token'),
      'tok-legacy',
    );
  });

  test('un vecchio token scaduto si cancella senza migrarlo', () async {
    final expiredAt = DateTime.now().subtract(const Duration(minutes: 1));
    SharedPreferences.setMockInitialValues({
      'paywall_unlock_token': 'tok-old',
      'paywall_unlock_expires_at': expiredAt.toIso8601String(),
    });
    FlutterSecureStorage.setMockInitialValues({});

    final store = UnlockTokenStore.withStorage(const FlutterSecureStorage());

    expect(await store.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('paywall_unlock_token'), isNull);
    expect(
      await const FlutterSecureStorage().read(key: 'paywall_unlock_token'),
      isNull,
    );
  });
}
