/// Sostituto per il web: `image_picker` non scrive file (il percorso è un
/// URL `blob:` in memoria), quindi non c'è niente da cancellare.
String? parentDirectoryOf(String path) => null;

Future<void> deleteQuietly(String path) async {}

Future<void> deletePickerLeftovers(String? directory) async {}
