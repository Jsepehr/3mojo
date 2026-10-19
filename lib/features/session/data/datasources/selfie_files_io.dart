import 'dart:io';

/// Operazioni sui file della fotocamera (`image_picker`), solo dove esiste
/// un file system (Android/iOS/desktop). Sul web vedi `selfie_files_stub.dart`.
///
/// I nomi che usa `image_picker` (versioni 1.x):
/// - Android: `<uuid><numero>.jpg` nella cache dell'app, e `scaled_<stesso
///   nome>` se ridimensionato;
/// - iOS: `image_picker_<UUID>.jpg` in `tmp/`.
final RegExp _pickerFileName = RegExp(
  r'^(scaled_)?(image_picker_?)?'
  r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
  r'\d*\.(jpe?g|png|heic|webp)$',
);

String? parentDirectoryOf(String path) {
  if (path.isEmpty) return null;
  return File(path).parent.path;
}

Future<void> deleteQuietly(String path) async {
  if (path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Best-effort: un file già sparito o non cancellabile non blocca lo Start.
  }
}

/// Cancella, in [directory] (non nelle sottocartelle), ogni file che ha il
/// nome di uno scatto di `image_picker`.
Future<void> deletePickerLeftovers(String? directory) async {
  if (directory == null) return;
  try {
    final dir = Directory(directory);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (_pickerFileName.hasMatch(name)) await deleteQuietly(entity.path);
    }
  } catch (_) {
    // Best-effort.
  }
}
