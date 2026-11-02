import 'dart:io';

/// Permessi dei file che il server scrive su disco: leggibili solo dal
/// processo. Sia i record di moderazione sia lo stato degli sblocchi sono
/// già cifrati; questo è il secondo strato.

/// Crea [directory] (e i genitori) e la restringe a `700`. Best-effort: su un
/// filesystem che non supporta `chmod` (o su Windows) resta com'è.
Future<void> ensureSecureDirectory(Directory directory) async {
  await directory.create(recursive: true);
  await _chmod('700', directory.path);
}

/// Scrive [bytes] in [target] in modo **atomico** (file temporaneo accanto,
/// `flush`, `rename`) e con permessi `600`: il temporaneo è creato vuoto e
/// ristretto **prima** di ricevere i dati, quindi il contenuto non è mai
/// stato leggibile da altri utenti, nemmeno per un istante.
Future<void> writeFileAtomically600(File target, List<int> bytes) async {
  final temporary = File('${target.path}.tmp');
  await temporary.create(recursive: true);
  await _chmod('600', temporary.path);
  await temporary.writeAsBytes(bytes, flush: true);
  await temporary.rename(target.path);
}

/// I permessi di [path] in ottale (es. `600`), o `null` se non si
/// possono leggere (Windows). Per i test.
Future<String?> permissionsOf(String path) async {
  if (Platform.isWindows) return null;
  final mode = (await FileStat.stat(path)).mode & 0x1FF;
  return mode.toRadixString(8).padLeft(3, '0');
}

Future<void> _chmod(String mode, String path) async {
  if (Platform.isWindows) return;
  try {
    await Process.run('chmod', [mode, path]);
  } catch (_) {
    // Vedi sopra: best-effort.
  }
}
