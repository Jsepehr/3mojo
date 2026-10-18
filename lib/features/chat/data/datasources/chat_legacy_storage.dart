import 'package:shared_preferences/shared_preferences.dart';

/// Le versioni precedenti dell'app salvavano la cronologia della chat in
/// `shared_preferences`, in chiaro, e chi prendeva in mano il telefono poteva
/// leggerla anche dopo la fine dell'incontro. Ora la chat vive solo in
/// memoria: questa funzione cancella, una volta per avvio, quello che le
/// versioni vecchie avevano lasciato su disco (reale e modalità finta).
///
/// Mai bloccante e mai fatale: se lo storage non è disponibile (test, web
/// senza permessi...) non c'è niente da pulire.
Future<void> purgeLegacyChatStorage() async {
  if (_purged) return;
  _purged = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final legacyKeys = prefs.getKeys().where(
      (key) =>
          key == 'chat_conversations' ||
          key == 'fake_chat_conversations' ||
          key.startsWith('chat_messages_') ||
          key.startsWith('fake_chat_messages_'),
    );
    for (final key in legacyKeys.toList()) {
      await prefs.remove(key);
    }
  } catch (_) {
    // Niente storage, niente da pulire.
  }
}

bool _purged = false;
