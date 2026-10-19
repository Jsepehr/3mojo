import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '/core/errors/exceptions.dart';
import 'selfie_files_stub.dart'
    if (dart.library.io) 'selfie_files_io.dart'
    as files;
import 'selfie_local_data_source.dart';

/// Implementazione **reale** con `image_picker`. La fotocamera scrive lo
/// scatto in un file (cache/tmp dell'app): qui lo si legge in memoria e lo
/// si cancella **subito**, insieme a ogni altro scatto rimasto nella stessa
/// cartella (un "Rifai" precedente, un processo chiuso a metà, l'originale
/// non ridimensionato). Da qui in poi il selfie esiste solo come byte.
///
/// Lo scatto è già ridotto all'origine ([maxSide] px, qualità
/// [imageQuality]): niente foto da 12 MP in memoria. La preparazione per il
/// server (EXIF tolto, 640 px) resta in `NearbyRemoteDataSourceImpl`.
class SelfieLocalDataSourceImpl implements SelfieLocalDataSource {
  SelfieLocalDataSourceImpl({
    Future<XFile?> Function()? pickImage,
    Future<Uint8List> Function(Uint8List bytes)? flip,
  }) : _pickImage = pickImage ?? _pickFromFrontCamera,
       _flip = flip ?? _flipInBackground;

  static const double maxSide = 1280;
  static const int imageQuality = 85;

  final Future<XFile?> Function() _pickImage;
  final Future<Uint8List> Function(Uint8List bytes) _flip;

  /// Dove la fotocamera ha scritto l'ultimo scatto: è lì che si cerca
  /// cosa cancellare.
  String? _pickerDirectory;

  static Future<XFile?> _pickFromFrontCamera() => ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.front,
    maxWidth: maxSide,
    maxHeight: maxSide,
    imageQuality: imageQuality,
  );

  @override
  Future<Uint8List?> takeSelfie() async {
    // Prima di un nuovo scatto: via quello di prima, se fosse rimasto.
    await discardLeftoverFiles();

    final XFile? picked;
    try {
      picked = await _pickImage();
    } catch (e) {
      throw CacheException('Camera unavailable: ${e.runtimeType}');
    }
    if (picked == null) return null;

    _pickerDirectory = files.parentDirectoryOf(picked.path) ?? _pickerDirectory;
    try {
      return await picked.readAsBytes();
    } catch (e) {
      throw CacheException('Selfie unreadable: ${e.runtimeType}');
    } finally {
      await files.deleteQuietly(picked.path);
      await discardLeftoverFiles();
    }
  }

  @override
  Future<Uint8List> flipHorizontally(Uint8List selfieBytes) async {
    try {
      return await _flip(selfieBytes);
    } catch (e) {
      throw CacheException('Selfie not flipped: ${e.runtimeType}');
    }
  }

  @override
  Future<void> discardLeftoverFiles() =>
      files.deletePickerLeftovers(_pickerDirectory);
}

/// Decode/encode JPEG su un isolate separato (`compute`): non blocca il
/// frame in corso.
Future<Uint8List> _flipInBackground(Uint8List bytes) =>
    compute(flipSelfieBytes, bytes);

/// Ribalta orizzontalmente un JPEG. Il ribaltamento va fatto sull'immagine
/// **già raddrizzata**: ribaltando i pixel grezzi di una foto con EXIF
/// "ruotata di 90°" e lasciando l'EXIF, una volta raddrizzata (a schermo o
/// in `prepareSelfieForUpload`) risulterebbe ribaltata in verticale. Il
/// decoder di `package:image` 4.x applica già l'orientamento ai pixel;
/// `bakeOrientation` resta come garanzia se un formato non lo facesse, e
/// tutti i metadati (orientamento, posizione dello scatto...) vengono tolti.
/// Pubblica (top-level) perché `compute` la deve poter chiamare in un altro
/// isolate, e per i test. Se non si decodifica, la ritorna com'è.
Uint8List flipSelfieBytes(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return bytes;
  }
  if (decoded == null) return bytes;
  final flipped = img.flipHorizontal(img.bakeOrientation(decoded));
  flipped.exif = img.ExifData();
  return Uint8List.fromList(img.encodeJpg(flipped, quality: 90));
}
